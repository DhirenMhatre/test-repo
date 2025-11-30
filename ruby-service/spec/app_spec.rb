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
    it 'returns healthy for services when upstream health is 200' do
      allow(HTTParty).to receive(:get).with("#{PolyglotAPI.settings.go_service_url}/health",
                                            any_args).and_return(double(code: 200))
      allow(HTTParty).to receive(:get).with("#{PolyglotAPI.settings.python_service_url}/health",
                                            any_args).and_return(double(code: 200))

      get '/status'
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['services']['ruby']['status']).to eq('healthy')
      expect(body['services']['go']['status']).to eq('healthy')
      expect(body['services']['python']['status']).to eq('healthy')
    end

    it 'marks a service unreachable on error' do
      allow(HTTParty).to receive(:get).with("#{PolyglotAPI.settings.go_service_url}/health",
                                            any_args).and_return(double(code: 200))
      allow(HTTParty).to receive(:get).with("#{PolyglotAPI.settings.python_service_url}/health",
                                            any_args).and_raise(StandardError.new('connection failed'))

      get '/status'
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['services']['go']['status']).to eq('healthy')
      expect(body['services']['python']['status']).to eq('unreachable')
      expect(body['services']['python']['error']).to include('connection failed')
    end
  end

  describe 'POST /diff' do
    it 'returns 400 when old_content or new_content is missing' do
      post '/diff', {}.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      body = JSON.parse(last_response.body)
      expect(body['error']).to include('Missing old_content or new_content')
    end

    it 'returns diff and review for valid request' do
      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .with('/diff', hash_including(:old_content, :new_content))
        .and_return({ 'changes' => 3 })
      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .with('/review', hash_including(:content))
        .and_return({ 'score' => 95, 'issues' => [] })

      post '/diff', { old_content: 'a', new_content: 'b' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['diff']).to eq({ 'changes' => 3 })
      expect(body['new_code_review']).to eq({ 'score' => 95, 'issues' => [] })
    end
  end

  describe 'POST /metrics' do
    it 'returns 400 when content is missing' do
      post '/metrics', {}.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      body = JSON.parse(last_response.body)
      expect(body['error']).to include('Missing content')
    end

    it 'returns metrics, review, and computed overall quality' do
      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .with('/metrics', { content: 'x' })
        .and_return({ 'complexity' => 2 })
      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .with('/review', { content: 'x' })
        .and_return({ 'score' => 90, 'issues' => [{}] })

      post '/metrics', { content: 'x' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['metrics']).to eq({ 'complexity' => 2 })
      expect(body['review']).to eq({ 'score' => 90, 'issues' => [{}] })
      expect(body['overall_quality']).to eq(20.0)
    end
  end

  describe 'POST /dashboard' do
    it 'returns 400 when files array is missing or empty' do
      post '/dashboard', {}.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(400)
      body = JSON.parse(last_response.body)
      expect(body['error']).to include('Missing files array')
    end

    it 'returns aggregated dashboard statistics and health score' do
      allow_any_instance_of(PolyglotAPI).to receive(:call_go_service)
        .with('/statistics', { files: ['a.rb', 'b.py'] })
        .and_return({ 'total_files' => 5, 'total_lines' => 200, 'languages' => { 'ruby' => 3 } })
      allow_any_instance_of(PolyglotAPI).to receive(:call_python_service)
        .with('/statistics', { files: ['a.rb', 'b.py'] })
        .and_return({ 'average_score' => 80.0, 'total_issues' => 10, 'average_complexity' => 0.5 })

      post '/dashboard', { files: ['a.rb', 'b.py'] }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body).to have_key('timestamp')
      expect(body['file_statistics']).to eq({ 'total_files' => 5, 'total_lines' => 200,
                                              'languages' => { 'ruby' => 3 } })
      expect(body['review_statistics']).to eq({ 'average_score' => 80.0, 'total_issues' => 10,
                                                'average_complexity' => 0.5 })
      expect(body['summary']['total_files']).to eq(5)
      expect(body['summary']['total_lines']).to eq(200)
      expect(body['summary']['languages']).to eq({ 'ruby' => 3 })
      expect(body['summary']['average_quality_score']).to eq(80.0)
      expect(body['summary']['total_issues']).to eq(10)
      expect(body['summary']['health_score']).to eq(61.0)
    end
  end

  describe 'GET /traces' do
    it 'returns all traces' do
      traces = [{ 'id' => 'a', 'path' => '/analyze' }, { 'id' => 'b', 'path' => '/metrics' }]
      allow(CorrelationIdMiddleware).to receive(:all_traces).and_return(traces)

      get '/traces'
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['total_traces']).to eq(2)
      expect(body['traces']).to eq(traces)
    end
  end

  describe 'GET /traces/:correlation_id' do
    it 'returns 404 when no traces found' do
      allow(CorrelationIdMiddleware).to receive(:get_traces).with('abc').and_return([])

      get '/traces/abc'
      expect(last_response.status).to eq(404)
      body = JSON.parse(last_response.body)
      expect(body['error']).to include('No traces found')
    end

    it 'returns traces for a given correlation id' do
      traces = [{ 'step' => 1 }, { 'step' => 2 }]
      allow(CorrelationIdMiddleware).to receive(:get_traces).with('cid-1').and_return(traces)

      get '/traces/cid-1'
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['correlation_id']).to eq('cid-1')
      expect(body['trace_count']).to eq(2)
      expect(body['traces']).to eq(traces)
    end
  end

  describe 'GET /validation/errors' do
    it 'returns validation errors and total count' do
      errs = [{ 'field' => 'content', 'message' => 'required' }, { 'field' => 'path', 'message' => 'invalid' }]
      allow(RequestValidator).to receive(:get_validation_errors).and_return(errs)

      get '/validation/errors'
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['total_errors']).to eq(2)
      expect(body['errors']).to eq(errs)
    end
  end

  describe 'DELETE /validation/errors' do
    it 'clears validation errors' do
      expect(RequestValidator).to receive(:clear_validation_errors)

      delete '/validation/errors'
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body['message']).to eq('Validation errors cleared')
    end
  end

  describe 'private helper methods' do
    let(:instance) do
      described_class.new!
    end

    describe '#call_go_service' do
      it 'posts to Go service and returns parsed JSON' do
        response = double(body: { ok: true }.to_json)
        expect(HTTParty).to receive(:post) do |url, opts|
          expect(url).to eq("#{PolyglotAPI.settings.go_service_url}/parse")
          expect(opts[:headers]['Content-Type']).to eq('application/json')
          expect(opts[:headers][CorrelationIdMiddleware::CORRELATION_ID_HEADER]).to eq('cid-123')
          expect(JSON.parse(opts[:body])).to eq({ 'a' => 1 })
          response
        end

        result = instance.send(:call_go_service, '/parse', { a: 1 }, 'cid-123')
        expect(result).to eq({ 'ok' => true })
      end

      it 'returns an error hash when HTTP call fails' do
        allow(HTTParty).to receive(:post).and_raise(StandardError.new('timeout'))
        result = instance.send(:call_go_service, '/parse', { a: 1 })
        expect(result['error']).to include('timeout')
      end
    end

    describe '#call_python_service' do
      it 'posts to Python service and returns parsed JSON' do
        response = double(body: { ok: 'py' }.to_json)
        expect(HTTParty).to receive(:post) do |url, opts|
          expect(url).to eq("#{PolyglotAPI.settings.python_service_url}/review")
          expect(opts[:headers]['Content-Type']).to eq('application/json')
          expect(opts[:headers][CorrelationIdMiddleware::CORRELATION_ID_HEADER]).to eq('cid-xyz')
          expect(JSON.parse(opts[:body])).to eq({ 'code' => 'print(1)' })
          response
        end

        result = instance.send(:call_python_service, '/review', { code: 'print(1)' }, 'cid-xyz')
        expect(result).to eq({ 'ok' => 'py' })
      end

      it 'returns an error hash when HTTP call fails' do
        allow(HTTParty).to receive(:post).and_raise(StandardError.new('boom'))
        result = instance.send(:call_python_service, '/review', { x: 1 })
        expect(result['error']).to include('boom')
      end
    end

    describe '#detect_language' do
      it 'detects language based on file extension' do
        expect(instance.send(:detect_language, 'main.go')).to eq('go')
        expect(instance.send(:detect_language, 'script.py')).to eq('python')
        expect(instance.send(:detect_language, 'app.rb')).to eq('ruby')
        expect(instance.send(:detect_language, 'index.js')).to eq('javascript')
        expect(instance.send(:detect_language, 'types.ts')).to eq('typescript')
        expect(instance.send(:detect_language, 'Main.java')).to eq('java')
      end

      it 'returns unknown for unsupported or missing extensions' do
        expect(instance.send(:detect_language, 'README')).to eq('unknown')
        expect(instance.send(:detect_language, 'file.unknown')).to eq('unknown')
      end
    end

    describe '#calculate_quality_score' do
      it 'computes a bounded quality score' do
        metrics = { 'complexity' => 1 }
        review = { 'score' => 100, 'issues' => [{}] }
        expect(instance.send(:calculate_quality_score, metrics, review)).to eq(40.0)
      end

      it 'returns 0.0 when metrics or review contain error' do
        metrics = { 'error' => 'oops' }
        review = { 'score' => 90, 'issues' => [] }
        expect(instance.send(:calculate_quality_score, metrics, review)).to eq(0.0)
      end

      it 'clamps score to a maximum of 100' do
        metrics = { 'complexity' => 0 }
        review = { 'score' => 150, 'issues' => [] }
        expect(instance.send(:calculate_quality_score, metrics, review)).to eq(100)
      end
    end

    describe '#calculate_dashboard_health_score' do
      it 'computes health score with penalties' do
        file_stats = { 'total_files' => 5, 'total_lines' => 200 }
        review_stats = { 'average_score' => 80.0, 'total_issues' => 10, 'average_complexity' => 0.5 }
        expect(instance.send(:calculate_dashboard_health_score, file_stats, review_stats)).to eq(61.0)
      end

      it 'returns 0.0 when inputs contain error' do
        file_stats = { 'error' => 'bad' }
        review_stats = { 'average_score' => 80.0, 'total_issues' => 10, 'average_complexity' => 0.5 }
        expect(instance.send(:calculate_dashboard_health_score, file_stats, review_stats)).to eq(0.0)
      end

      it 'clamps health score between 0 and 100' do
        low_file_stats = { 'total_files' => 1 }
        low_review_stats = { 'average_score' => 10, 'total_issues' => 100, 'average_complexity' => 1.0 }
        expect(instance.send(:calculate_dashboard_health_score, low_file_stats, low_review_stats)).to eq(0.0)

        high_file_stats = { 'total_files' => 10 }
        high_review_stats = { 'average_score' => 200, 'total_issues' => 0, 'average_complexity' => 0.0 }
        expect(instance.send(:calculate_dashboard_health_score, high_file_stats, high_review_stats)).to eq(100)
      end
    end
  end
end
