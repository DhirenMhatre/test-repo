# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/json'
require 'rack/cors'
require 'httparty'
require 'json'
require_relative 'services/session_store'
require_relative 'services/analytics_tracker'
require_relative 'services/request_cache'
require_relative 'services/authorization_manager'
require_relative 'services/api_token_manager'

class PolyglotAPI < Sinatra::Base
  use Rack::Cors do
    allow do
      origins '*'
      resource '*', headers: :any, methods: %i[get post put delete options]
    end
  end

  configure do
    set :go_service_url, ENV['GO_SERVICE_URL'] || 'http://localhost:8080'
    set :python_service_url, ENV['PYTHON_SERVICE_URL'] || 'http://localhost:8081'
    set :session_store, SessionStore.new
    set :analytics, AnalyticsTracker.new
    set :cache, RequestCache.new
    set :authz, AuthorizationManager.new
    set :token_manager, ApiTokenManager.new
  end

  get '/health' do
    json status: 'healthy', service: 'ruby-api'
  end

  get '/status' do
    services_status = {
      ruby: { status: 'healthy' },
      go: check_service_health(settings.go_service_url),
      python: check_service_health(settings.python_service_url)
    }
    json services: services_status
  end

  post '/analyze' do
    begin
      body = request.body.read
      request.body.rewind
      request_data = body.empty? ? params : JSON.parse(body)
    rescue JSON::ParserError
      request_data = params
    end
    content = request_data['content'] || request_data[:content]
    path = request_data['path'] || request_data[:path] || 'unknown'

    return json(error: 'Missing content'), 400 unless content

    cached = settings.cache.get(request_data)
    return json(cached) if cached

    go_result = call_go_service('/parse', { content: content, path: path })
    python_result = call_python_service('/review', { content: content, language: detect_language(path) })

    result = {
      file_info: go_result,
      review: python_result,
      summary: {
        language: go_result['language'],
        lines: go_result['lines']&.length || 0,
        review_score: python_result['score'],
        issues_count: python_result['issues']&.length || 0
      }
    }

    settings.cache.set(request_data, result)

    user_id = get_authenticated_user_id
    if user_id
      settings.analytics.track_event(user_id, 'code_analysis', {
        language: go_result['language'],
        score: python_result['score']
      })
    end

    json(result)
  end

  post '/diff' do
    begin
      body = request.body.read
      request.body.rewind
      request_data = body.empty? ? params : JSON.parse(body)
    rescue JSON::ParserError
      request_data = params
    end
    old_content = request_data['old_content'] || request_data[:old_content]
    new_content = request_data['new_content'] || request_data[:new_content]

    return json(error: 'Missing old_content or new_content'), 400 unless old_content && new_content

    diff_result = call_go_service('/diff', { old_content: old_content, new_content: new_content })
    new_review = call_python_service('/review', { content: new_content })

    json(
      diff: diff_result,
      new_code_review: new_review
    )
  end

  post '/metrics' do
    begin
      body = request.body.read
      request.body.rewind
      request_data = body.empty? ? params : JSON.parse(body)
    rescue JSON::ParserError
      request_data = params
    end
    content = request_data['content'] || request_data[:content]

    return json(error: 'Missing content'), 400 unless content

    metrics = call_go_service('/metrics', { content: content })
    review = call_python_service('/review', { content: content })

    json(
      metrics: metrics,
      review: review,
      overall_quality: calculate_quality_score(metrics, review)
    )
  end

  private

  def check_service_health(url)
    response = HTTParty.get("#{url}/health", timeout: 2)
    { status: response.code == 200 ? 'healthy' : 'unhealthy' }
  rescue StandardError => e
    { status: 'unreachable', error: e.message }
  end

  def call_go_service(endpoint, data)
    response = HTTParty.post(
      "#{settings.go_service_url}#{endpoint}",
      body: data.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 5
    )
    JSON.parse(response.body)
  rescue StandardError => e
    { error: e.message }
  end

  def call_python_service(endpoint, data)
    response = HTTParty.post(
      "#{settings.python_service_url}#{endpoint}",
      body: data.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 5
    )
    JSON.parse(response.body)
  rescue StandardError => e
    { error: e.message }
  end

  def detect_language(path)
    ext = File.extname(path).downcase
    lang_map = {
      '.go' => 'go',
      '.py' => 'python',
      '.rb' => 'ruby',
      '.js' => 'javascript',
      '.ts' => 'typescript',
      '.java' => 'java'
    }
    lang_map[ext] || 'unknown'
  end

  def calculate_quality_score(metrics, review)
    return 0.0 unless metrics && review && !metrics['error'] && !review['error']

    complexity_penalty = (metrics['complexity'] || 0) * 0.1
    issue_penalty = (review['issues']&.length || 0) * 0.5
    review_score = review['score'] || 0

    base_score = review_score / 100.0
    final_score = base_score - complexity_penalty - issue_penalty

    score = (final_score * 100).round(2)
    score.clamp(0, 100)
  end

  def get_authenticated_user_id
    token = request.env['HTTP_AUTHORIZATION']&.sub(/^Bearer /, '')
    return nil unless token

    begin
      settings.token_manager.verify_token(token)
    rescue StandardError
      nil
    end
  end

  def require_auth
    user_id = get_authenticated_user_id
    halt 401, json(error: 'Unauthorized') unless user_id
    user_id
  end

  def require_permission(action)
    user_id = require_auth
    token = request.env['HTTP_AUTHORIZATION']&.sub(/^Bearer /, '')
    role = settings.token_manager.get_token_scope(token)

    unless settings.authz.can_perform?(role, action)
      halt 403, json(error: 'Forbidden')
    end

    user_id
  end

  post '/auth/session' do
    begin
      data = JSON.parse(request.body.read)
    rescue JSON::ParserError
      halt 400, json(error: 'Invalid JSON')
    end

    user_id = data['user_id']
    role = data['role'] || 'viewer'

    halt 400, json(error: 'Missing user_id') unless user_id

    session_token = settings.session_store.create(user_id, { role: role })
    api_token = settings.token_manager.generate_token(user_id, scope: role)

    json(session_token: session_token, api_token: api_token)
  end

  delete '/auth/session' do
    user_id = require_auth
    token = request.env['HTTP_AUTHORIZATION']&.sub(/^Bearer /, '')

    settings.token_manager.revoke_token(token) if token
    json(success: true)
  end

  get '/analytics/user/:user_id' do
    require_permission('read')

    user_id = params['user_id']
    events = settings.analytics.get_user_events(user_id)
    score = settings.analytics.compute_user_score(user_id)

    json(events: events, average_score: score)
  end

  post '/analytics/event' do
    user_id = require_auth

    begin
      data = JSON.parse(request.body.read)
    rescue JSON::ParserError
      halt 400, json(error: 'Invalid JSON')
    end

    event_type = data['event_type']
    event_data = data['data'] || {}

    halt 400, json(error: 'Missing event_type') unless event_type

    settings.analytics.track_event(user_id, event_type, event_data)
    json(success: true)
  end

  get '/analytics/events' do
    require_permission('read')

    event_type = params['type']
    events = event_type ? settings.analytics.get_events_by_type(event_type) : settings.analytics.get_all_events

    json(events: events, count: events.length)
  end

  post '/cache/invalidate' do
    require_permission('write')

    begin
      data = JSON.parse(request.body.read)
    rescue JSON::ParserError
      halt 400, json(error: 'Invalid JSON')
    end

    settings.cache.invalidate(data)

    json(success: true)
  end

  get '/admin/sessions' do
    require_permission('manage_users')

    sessions = settings.session_store.all_sessions
    json(sessions: sessions, count: sessions.length)
  end
end
