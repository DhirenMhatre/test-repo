# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../app/app'

RSpec.describe PolyglotAPI do
  include Rack::Test::Methods

  def app
    PolyglotAPI
  end

  describe 'GET /health' do
    it 'returns healthy status' do
      get '/health'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['status']).to eq('healthy')
    end
  end

  describe 'POST /analyze' do
    it 'accepts valid content' do
      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .and_return({ 'language' => 'python', 'lines' => ['def test'] })
      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .and_return({ 'score' => 85.0, 'issues' => [] })

      post '/analyze', { content: 'def test(): pass', path: 'test.py' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response).to have_key('summary')
    end
  end

  describe 'GET /status' do
    it 'returns aggregated service statuses' do
      allow_any_instance_of(PolyglotAPI).to receive(:check_service_health) do |_, url|
        if url.include?('8080')
          { status: 'healthy' }
        elsif url.include?('8081')
          { status: 'unreachable', error: 'timeout' }
        else
          { status: 'unknown' }
        end
      end

      get '/status'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['services']).to include('ruby', 'go', 'python')
      expect(json_response['services']['ruby']['status']).to eq('healthy')
      expect(json_response['services']['go']['status']).to eq('healthy')
      expect(json_response['services']['python']['status']).to eq('unreachable')
    end
  end

  describe 'POST /analyze validations and headers' do
    let(:corr_header) { CorrelationIdMiddleware::CORRELATION_ID_HEADER }
    let(:corr_id) { 'corr-123' }

    before do
      allow(RequestValidator).to receive(:validate_analyze_request).and_return([])
      allow(RequestValidator).to receive(:sanitize_input) { |arg| arg }
    end

    it 'returns 422 when validation fails' do
      err_obj = double('ValidationError', to_hash: { field: 'content', message: 'is required' })
      allow(RequestValidator).to receive(:validate_analyze_request).and_return([err_obj])

      post '/analyze', {}.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(422)
      json_response = JSON.parse(last_response.body)
      expect(json_response['error']).to eq('Validation failed')
      expect(json_response['details']).to be_an(Array)
      expect(json_response['details'].first['field']).to eq('content')
    end

    it 'propagates correlation id to downstream services and detects language from path' do
      header corr_header, corr_id

      expect_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .with('/parse', hash_including({ content: 'puts 1', path: 'app.rb' }), corr_id)
        .and_return({ 'language' => 'ruby', 'lines' => ['puts 1'] })

      expect_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .with('/review', hash_including({ content: 'puts 1', language: 'ruby' }), corr_id)
        .and_return({ 'score' => 75.0, 'issues' => [] })

      post '/analyze', { content: 'puts 1', path: 'app.rb' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['correlation_id']).to eq(corr_id)
      expect(body['summary']['language']).to eq('ruby')
    end
  end

  describe 'POST /diff' do
    it 'returns 400 when missing old_content or new_content' do
      post '/diff', { old_content: 'a' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      json_response = JSON.parse(last_response.body)
      expect(json_response['error']).to eq('Missing old_content or new_content')
    end

    it 'returns diff and new code review on success' do
      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .with('/diff', hash_including({ old_content: 'a', new_content: 'b' }))
        .and_return({ 'changes' => 1 })

      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .with('/review', hash_including({ content: 'b' }))
        .and_return({ 'score' => 80.0, 'issues' => [] })

      post '/diff', { old_content: 'a', new_content: 'b' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['diff']).to eq('changes' => 1)
      expect(json_response['new_code_review']).to eq('score' => 80.0, 'issues' => [])
    end
  end

  describe 'POST /metrics' do
    it 'returns 400 when content is missing' do
      post '/metrics', {}.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      json_response = JSON.parse(last_response.body)
      expect(json_response['error']).to eq('Missing content')
    end

    it 'returns metrics, review, and calculated overall_quality' do
      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .with('/metrics', hash_including({ content: 'code' }))
        .and_return({ 'complexity' => 1 })

      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .with('/review', hash_including({ content: 'code' }))
        .and_return({ 'score' => 90, 'issues' => ['x'] })

      post '/metrics', { content: 'code' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['overall_quality']).to eq(30.0)
    end

    it 'returns overall_quality 0 when metrics returns error' do
      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .and_return({ 'error' => 'timeout' })

      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .and_return({ 'score' => 90, 'issues' => [] })

      post '/metrics', { content: 'code' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['overall_quality']).to eq(0.0)
    end
  end

  describe 'POST /dashboard' do
    it 'returns 400 when files array is missing or empty' do
      post '/dashboard', {}.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      json_response = JSON.parse(last_response.body)
      expect(json_response['error']).to eq('Missing files array')
    end

    it 'returns statistics and calculated health score' do
      file_stats = {
        'total_files' => 5,
        'total_lines' => 100,
        'languages' => { 'ruby' => 5 }
      }
      review_stats = {
        'average_score' => 90.0,
        'total_issues' => 10,
        'average_complexity' => 1.0
      }
      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .with('/statistics', hash_including({ files: ['a.rb', 'b.rb'] }))
        .and_return(file_stats)

      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .with('/statistics', hash_including({ files: ['a.rb', 'b.rb'] }))
        .and_return(review_stats)

      post '/dashboard', { files: ['a.rb', 'b.rb'] }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response).to have_key('timestamp')
      expect(json_response['file_statistics']).to eq(file_stats)
      expect(json_response['review_statistics']).to eq(review_stats)
      expect(json_response['summary']['total_files']).to eq(5)
      expect(json_response['summary']['total_lines']).to eq(100)
      expect(json_response['summary']['average_quality_score']).to eq(90.0)
      expect(json_response['summary']['total_issues']).to eq(10)
      expect(json_response['summary']['health_score']).to eq(56.0)
    end
  end

  describe 'GET /traces' do
    it 'returns a list of all traces with count' do
      traces = [
        { id: 'a', steps: [] },
        { id: 'b', steps: [1] }
      ]
      allow(CorrelationIdMiddleware).to receive(:all_traces).and_return(traces)

      get '/traces'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['total_traces']).to eq(2)
      expect(json_response['traces']).to be_an(Array)
    end
  end

  describe 'GET /traces/:correlation_id' do
    it 'returns 404 when no traces found' do
      allow(CorrelationIdMiddleware).to receive(:get_traces).with('none').and_return([])

      get '/traces/none'
      expect(last_response.status).to eq(404)
      json_response = JSON.parse(last_response.body)
      expect(json_response['error']).to eq('No traces found for correlation ID')
    end

    it 'returns traces for the given correlation id' do
      traces = [{ step: 'start' }, { step: 'end' }]
      allow(CorrelationIdMiddleware).to receive(:get_traces).with('abc').and_return(traces)

      get '/traces/abc'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['correlation_id']).to eq('abc')
      expect(json_response['trace_count']).to eq(2)
      expect(json_response['traces']).to eq(traces)
    end
  end

  describe 'Validation errors endpoints' do
    it 'GET /validation/errors returns stored errors' do
      errs = [{ field: 'content', message: 'bad' }]
      allow(RequestValidator).to receive(:get_validation_errors).and_return(errs)

      get '/validation/errors'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['total_errors']).to eq(1)
      expect(json_response['errors']).to eq(errs)
    end

    it 'DELETE /validation/errors clears stored errors' do
      expect(RequestValidator).to receive(:clear_validation_errors)

      delete '/validation/errors'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['message']).to eq('Validation errors cleared')
    end
  end
end
