# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../app/app'
require 'time'

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
    context 'when dependent services are healthy' do
      it 'returns services status as healthy' do
        allow(HTTParty).to receive(:get).with('http://localhost:8080/health', timeout: 2).and_return(double(code: 200))
        allow(HTTParty).to receive(:get).with('http://localhost:8081/health', timeout: 2).and_return(double(code: 200))

        get '/status'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['services']['ruby']['status']).to eq('healthy')
        expect(json_response['services']['go']['status']).to eq('healthy')
        expect(json_response['services']['python']['status']).to eq('healthy')
      end
    end

    context 'when a service is unreachable' do
      it 'marks the service as unreachable with error message' do
        allow(HTTParty).to receive(:get).with('http://localhost:8080/health', timeout: 2).and_return(double(code: 200))
        allow(HTTParty).to receive(:get).with('http://localhost:8081/health',
                                              timeout: 2).and_raise(StandardError.new('connection refused'))

        get '/status'
        expect(last_response.status).to eq(200)
        json_response = JSON.parse(last_response.body)
        expect(json_response['services']['go']['status']).to eq('healthy')
        expect(json_response['services']['python']['status']).to eq('unreachable')
        expect(json_response['services']['python']['error']).to include('connection refused')
      end
    end
  end

  describe 'POST /analyze validation' do
    it 'returns 422 when validation fails' do
      allow(RequestValidator).to receive(:validate_analyze_request).and_return([double(to_hash: { field: 'content',
                                                                                                  message: 'is required' })])
      post '/analyze', { path: 'file.py' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(422)
      json_response = JSON.parse(last_response.body)
      expect(json_response['error']).to eq('Validation failed')
      expect(json_response['details']).to be_an(Array)
      expect(json_response['details'].first['field']).to eq('content')
    end

    it 'propagates correlation id to downstream services' do
      header_key = CorrelationIdMiddleware::CORRELATION_ID_HEADER
      correlation_id = 'abc-123'
      expect_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .with('/parse', kind_of(Hash), correlation_id)
        .and_return({ 'language' => 'ruby', 'lines' => ['puts 1'] })
      expect_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .with('/review', kind_of(Hash), correlation_id)
        .and_return({ 'score' => 95.0, 'issues' => [] })

      post '/analyze', { content: 'puts 1', path: 'test.rb' }.to_json,
           { 'CONTENT_TYPE' => 'application/json', header_key => correlation_id }
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['correlation_id']).to eq(correlation_id)
    end
  end

  describe 'POST /diff' do
    it 'returns 400 when required params are missing' do
      post '/diff', {}.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      json_response = JSON.parse(last_response.body)
      expect(json_response['error']).to eq('Missing old_content or new_content')
    end

    it 'returns diff and new review when params are provided' do
      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .and_return({ 'changes' => 3 })
      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .and_return({ 'score' => 80, 'issues' => [1] })

      post '/diff', { old_content: 'a', new_content: 'b' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['diff']).to eq({ 'changes' => 3 })
      expect(json_response['new_code_review']).to eq({ 'score' => 80, 'issues' => [1] })
    end
  end

  describe 'POST /metrics' do
    it 'returns 400 when content is missing' do
      post '/metrics', {}.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      json_response = JSON.parse(last_response.body)
      expect(json_response['error']).to eq('Missing content')
    end

    it 'returns metrics, review, and overall_quality' do
      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .and_return({ 'complexity' => 1 })
      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .and_return({ 'score' => 80, 'issues' => ['x'] })

      post '/metrics', { content: 'code' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['metrics']).to eq({ 'complexity' => 1 })
      expect(json_response['review']).to eq({ 'score' => 80, 'issues' => ['x'] })
      expect(json_response['overall_quality']).to eq(20.0)
    end
  end

  describe 'POST /dashboard' do
    it 'returns 400 when files array is missing or empty' do
      post '/dashboard', {}.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      json_response = JSON.parse(last_response.body)
      expect(json_response['error']).to eq('Missing files array')
    end

    it 'returns aggregated dashboard data with summary and timestamp' do
      fixed_time = Time.utc(2024, 1, 2, 3, 4, 5)
      allow(Time).to receive(:now).and_return(fixed_time)

      file_stats = { 'total_files' => 3, 'total_lines' => 100, 'languages' => { 'ruby' => 2 } }
      review_stats = { 'average_score' => 88.5, 'total_issues' => 6, 'average_complexity' => 0.1 }

      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .and_return(file_stats)
      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .and_return(review_stats)

      post '/dashboard', { files: [{ path: 'a.rb' }, { path: 'b.rb' }] }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['timestamp']).to eq(fixed_time.iso8601)
      expect(json_response['file_statistics']).to eq(file_stats)
      expect(json_response['review_statistics']).to eq(review_stats)
      expect(json_response['summary']['total_files']).to eq(3)
      expect(json_response['summary']['total_lines']).to eq(100)
      expect(json_response['summary']['languages']).to eq({ 'ruby' => 2 })
      expect(json_response['summary']['average_quality_score']).to eq(88.5)
      expect(json_response['summary']['total_issues']).to eq(6)
      expect(json_response['summary']['health_score']).to eq(81.5)
    end
  end

  describe 'GET /traces' do
    it 'returns all traces with total count' do
      allow(CorrelationIdMiddleware).to receive(:all_traces).and_return([{ id: '1' }, { id: '2' }])
      get '/traces'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['total_traces']).to eq(2)
      expect(json_response['traces']).to eq([{ 'id' => '1' }, { 'id' => '2' }])
    end
  end

  describe 'GET /traces/:correlation_id' do
    it 'returns 404 when no traces are found' do
      allow(CorrelationIdMiddleware).to receive(:get_traces).with('abc').and_return([])
      get '/traces/abc'
      expect(last_response.status).to eq(404)
      json_response = JSON.parse(last_response.body)
      expect(json_response['error']).to eq('No traces found for correlation ID')
    end

    it 'returns traces for a specific correlation id' do
      traces = [{ step: 'start' }, { step: 'end' }]
      allow(CorrelationIdMiddleware).to receive(:get_traces).with('xyz').and_return(traces)
      get '/traces/xyz'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['correlation_id']).to eq('xyz')
      expect(json_response['trace_count']).to eq(2)
      expect(json_response['traces']).to eq([{ 'step' => 'start' }, { 'step' => 'end' }])
    end
  end

  describe 'Validation Errors endpoints' do
    it 'GET /validation/errors returns stored errors' do
      allow(RequestValidator).to receive(:get_validation_errors).and_return([{ field: 'x', error: 'bad' }])
      get '/validation/errors'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['total_errors']).to eq(1)
      expect(json_response['errors']).to eq([{ 'field' => 'x', 'error' => 'bad' }])
    end

    it 'DELETE /validation/errors clears errors' do
      expect(RequestValidator).to receive(:clear_validation_errors)
      delete '/validation/errors'
      expect(last_response.status).to eq(200)
      json_response = JSON.parse(last_response.body)
      expect(json_response['message']).to eq('Validation errors cleared')
    end
  end

  describe 'private helper methods' do
    let(:instance) { app.new }

    describe '#check_service_health' do
      it 'returns healthy on 200' do
        allow(HTTParty).to receive(:get).with('http://localhost:8080/health', timeout: 2).and_return(double(code: 200))
        result = instance.send(:check_service_health, 'http://localhost:8080')
        expect(result).to eq({ status: 'healthy' })
      end

      it 'returns unhealthy on non-200' do
        allow(HTTParty).to receive(:get).with('http://localhost:8080/health', timeout: 2).and_return(double(code: 500))
        result = instance.send(:check_service_health, 'http://localhost:8080')
        expect(result).to eq({ status: 'unhealthy' })
      end

      it 'returns unreachable on error' do
        allow(HTTParty).to receive(:get).with('http://localhost:8080/health',
                                              timeout: 2).and_raise(StandardError.new('boom'))
        result = instance.send(:check_service_health, 'http://localhost:8080')
        expect(result[:status]).to eq('unreachable')
        expect(result[:error]).to include('boom')
      end
    end

    describe '#call_go_service' do
      it 'posts to go service and parses JSON' do
        expect(HTTParty).to receive(:post).with(
          'http://localhost:8080/parse',
          hash_including(
            headers: hash_including('Content-Type' => 'application/json',
                                    CorrelationIdMiddleware::CORRELATION_ID_HEADER => 'cid'),
            body: kind_of(String),
            timeout: 5
          )
        ).and_return(double(body: '{"ok":true}'))
        result = instance.send(:call_go_service, '/parse', { a: 1 }, 'cid')
        expect(result).to eq({ 'ok' => true })
      end

      it 'returns error hash when request fails' do
        allow(HTTParty).to receive(:post).and_raise(StandardError.new('timeout'))
        result = instance.send(:call_go_service, '/parse', { a: 1 }, 'cid')
        expect(result['error']).to include('timeout')
      end
    end

    describe '#call_python_service' do
      it 'posts to python service and parses JSON' do
        expect(HTTParty).to receive(:post).with(
          'http://localhost:8081/review',
          hash_including(
            headers: hash_including('Content-Type' => 'application/json',
                                    CorrelationIdMiddleware::CORRELATION_ID_HEADER => 'pid'),
            body: kind_of(String),
            timeout: 5
          )
        ).and_return(double(body: '{"score": 99}'))
        result = instance.send(:call_python_service, '/review', { b: 2 }, 'pid')
        expect(result).to eq({ 'score' => 99 })
      end

      it 'returns error hash when request fails' do
        allow(HTTParty).to receive(:post).and_raise(StandardError.new('down'))
        result = instance.send(:call_python_service, '/review', { b: 2 }, 'pid')
        expect(result['error']).to include('down')
      end
    end

    describe '#detect_language' do
      it 'detects known languages by extension' do
        expect(instance.send(:detect_language, 'file.go')).to eq('go')
        expect(instance.send(:detect_language, 'file.py')).to eq('python')
        expect(instance.send(:detect_language, 'file.rb')).to eq('ruby')
        expect(instance.send(:detect_language, 'file.js')).to eq('javascript')
        expect(instance.send(:detect_language, 'file.ts')).to eq('typescript')
        expect(instance.send(:detect_language, 'file.java')).to eq('java')
      end

      it 'returns unknown for unrecognized extensions' do
        expect(instance.send(:detect_language, 'file.unknown')).to eq('unknown')
      end
    end

    describe '#calculate_quality_score' do
      it 'returns 0.0 when metrics has error' do
        result = instance.send(:calculate_quality_score, { 'error' => 'x' }, { 'score' => 80, 'issues' => [] })
        expect(result).to eq(0.0)
      end

      it 'returns 0.0 when review has error' do
        result = instance.send(:calculate_quality_score, { 'complexity' => 1 }, { 'error' => 'x' })
        expect(result).to eq(0.0)
      end

      it 'calculates and clamps score within 0..100' do
        result = instance.send(:calculate_quality_score, { 'complexity' => 0 }, { 'score' => 150, 'issues' => [] })
        expect(result).to eq(100)

        result2 = instance.send(:calculate_quality_score, { 'complexity' => 50 },
                                { 'score' => 10, 'issues' => Array.new(10) })
        expect(result2).to eq(0)
      end

      it 'computes expected score based on penalties' do
        result = instance.send(:calculate_quality_score, { 'complexity' => 1 }, { 'score' => 80, 'issues' => ['a'] })
        expect(result).to eq(20.0)
      end
    end

    describe '#calculate_dashboard_health_score' do
      it 'returns 0.0 when inputs have error' do
        result = instance.send(:calculate_dashboard_health_score, { 'error' => 'x' }, { 'average_score' => 50 })
        expect(result).to eq(0.0)

        result2 = instance.send(:calculate_dashboard_health_score, { 'total_files' => 1 }, { 'error' => 'x' })
        expect(result2).to eq(0.0)
      end

      it 'calculates health score within 0..100' do
        file_stats = { 'total_files' => 3 }
        review_stats = { 'average_score' => 88.5, 'total_issues' => 6, 'average_complexity' => 0.1 }
        result = instance.send(:calculate_dashboard_health_score, file_stats, review_stats)
        expect(result).to eq(81.5)
      end
    end
  end
end
