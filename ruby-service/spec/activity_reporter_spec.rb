require 'spec_helper'
require 'tmpdir'
require 'rails_helper'
require_relative '../../ruby-service/app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:go_url) { 'http://go.example:8080' }
  let(:py_url) { 'http://py.example:8081' }
  let(:reporter) { described_class.new(go_service_url: go_url, python_service_url: py_url) }
  let(:fixed_time) { Time.parse('2025-01-15 12:34:56 UTC') }

  before do
    allow(Time).to receive(:now).and_return(fixed_time)
  end

  describe '#initialize' do
    context 'with default urls' do
      let(:default_reporter) { described_class.new }

      it 'sets default service URLs' do
        expect(default_reporter.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
        expect(default_reporter.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
      end
    end

    context 'with custom urls' do
      it 'stores provided service URLs' do
        expect(reporter.instance_variable_get(:@go_service_url)).to eq(go_url)
        expect(reporter.instance_variable_get(:@python_service_url)).to eq(py_url)
      end
    end
  end

  describe '#generate_report' do
    let(:user_id) { 'user-123' }
    let(:activities) do
      [
        { 'timestamp' => '2025-01-10T10:15:00Z', 'action' => 'login' },
        { 'timestamp' => '2025-01-10T10:45:00Z', 'action' => 'upload' },
        { 'timestamp' => '2025-01-10T11:00:00Z', 'action' => 'login' }
      ]
    end
    let(:stats) do
      {
        total_actions: 150,
        unique_actions: 12,
        action_counts: { 'login' => 100, 'upload' => 50 },
        first_activity: '2025-01-01T00:00:00Z',
        last_activity: '2025-01-10T12:00:00Z',
        most_frequent: 'login'
      }
    end
    let(:patterns) do
      [
        { 'pattern_type' => 'sequence', 'description' => 'Login then Upload', 'confidence' => 0.82 },
        { 'pattern_type' => 'burst', 'description' => 'Morning activity burst', 'confidence' => 0.76 },
        { 'pattern_type' => 'periodic', 'description' => 'Daily login', 'confidence' => 0.9 }
      ]
    end
    let(:user_score) { 88.5 }
    let(:anomalies) { [{ 'type' => 'spike' }, { 'type' => 'rare_event' }] }

    before do
      allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
      allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
      allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
      allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
      allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
    end

    context 'when activities are present' do
      it 'returns a comprehensive report with hourly timeline and insights' do
        report = reporter.generate_report(user_id, group_by: :hour)

        expect(report[:user_id]).to eq(user_id)
        expect(report[:generated_at]).to eq(fixed_time.iso8601)

        expect(report[:summary][:total_actions]).to eq(stats[:total_actions])
        expect(report[:summary][:unique_actions]).to eq(stats[:unique_actions])
        expect(report[:summary][:engagement_score]).to eq(user_score)
        expect(report[:summary][:first_activity]).to eq(stats[:first_activity])
        expect(report[:summary][:last_activity]).to eq(stats[:last_activity])

        expect(report[:action_breakdown]).to eq(stats[:action_counts])

        expected_patterns = patterns.map do |p|
          { type: p['pattern_type'], description: p['description'], confidence: p['confidence'] }
        end
        expect(report[:patterns]).to eq(expected_patterns)

        expect(report[:anomalies]).to eq(anomalies)

        # Timeline expectations
        expect(report[:timeline]).to be_an(Array)
        periods = report[:timeline].map { |t| t[:period] }
        expect(periods).to eq(['2025-01-10 10:00', '2025-01-10 11:00'])
        t10 = report[:timeline].find { |t| t[:period] == '2025-01-10 10:00' }
        expect(t10[:total_actions]).to eq(2)
        expect(t10[:actions]).to eq({ 'login' => 1, 'upload' => 1 })
        expect(t10[:first_timestamp]).to eq('2025-01-10T10:15:00Z')
        expect(t10[:last_timestamp]).to eq('2025-01-10T10:45:00Z')

        # Insights expectations
        expect(report[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(report[:insights]).to include('Diverse activity profile across multiple action types')
        expect(report[:insights]).to include('Clear behavioral patterns detected')
        expect(report[:insights]).to include('2 anomalous activities detected - review recommended')
        expect(report[:insights]).to include('Power user - high volume of activities')
      end

      it 'falls back to daily timeline when unknown group_by is provided' do
        report = reporter.generate_report(user_id, group_by: :unknown)
        periods = report[:timeline].map { |t| t[:period] }.uniq
        expect(periods).to eq(['2025-01-10'])
      end
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report' do
        report = reporter.generate_report(user_id)
        expect(report[:error]).to eq(true)
        expect(report[:message]).to eq('No activities found')
        expect(report[:generated_at]).to eq(fixed_time.iso8601)
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities are empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([])).to eq([])
      end
    end

    context 'grouping by day' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-01T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T11:00:00Z', 'action' => 'upload' },
          { 'timestamp' => '2025-01-02T09:00:00Z', 'action' => 'login' }
        ]
      end

      it 'groups activities per day with counts and timestamps' do
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.length).to eq(2)
        expect(timeline[0][:period]).to eq('2025-01-01')
        expect(timeline[0][:total_actions]).to eq(2)
        expect(timeline[0][:actions]).to eq({ 'login' => 1, 'upload' => 1 })
        expect(timeline[0][:first_timestamp]).to eq('2025-01-01T10:15:00Z')
        expect(timeline[0][:last_timestamp]).to eq('2025-01-01T11:00:00Z')
        expect(timeline[1][:period]).to eq('2025-01-02')
        expect(timeline[1][:actions]).to eq({ 'login' => 1 })
      end
    end

    context 'grouping by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-03T08:05:00Z', 'action' => 'view' },
          { 'timestamp' => '2025-01-03T08:30:00Z', 'action' => 'view' },
          { 'timestamp' => '2025-01-03T09:00:00Z', 'action' => 'click' }
        ]
      end

      it 'groups activities per hour' do
        timeline = reporter.format_timeline(activities, :hour)
        expect(timeline.map { |t| t[:period] }).to eq(['2025-01-03 08:00', '2025-01-03 09:00'])
        expect(timeline.first[:actions]).to eq({ 'view' => 2 })
        expect(timeline.last[:actions]).to eq({ 'click' => 1 })
      end
    end

    context 'grouping by week' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-05T10:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2025-01-06T10:00:00Z', 'action' => 'b' }
        ]
      end

      it 'groups activities per ISO week' do
        timeline = reporter.format_timeline(activities, :week)
        expected_periods = activities.map { |a| Time.parse(a['timestamp']).strftime('%Y-W%V') }.uniq.sort
        expect(timeline.map { |t| t[:period] }).to eq(expected_periods)
      end
    end

    context 'grouping by month' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-31T23:59:59Z', 'action' => 'end' },
          { 'timestamp' => '2025-02-01T00:00:01Z', 'action' => 'start' }
        ]
      end

      it 'groups activities per month' do
        timeline = reporter.format_timeline(activities, :month)
        expect(timeline.map { |t| t[:period] }).to eq(%w[2025-01 2025-02])
      end
    end

    context 'with invalid timestamp' do
      let(:activities) do
        [
          { 'timestamp' => 'not-a-timestamp', 'action' => 'weird' }
        ]
      end

      it 'falls back to current time for grouping' do
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.length).to eq(1)
        expect(timeline.first[:period]).to eq(fixed_time.strftime('%Y-%m-%d'))
        expect(timeline.first[:actions]).to eq({ 'weird' => 1 })
      end
    end

    context 'with unknown grouping option' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-10T12:00:00Z', 'action' => 'x' }
        ]
      end

      it 'defaults to daily grouping' do
        timeline = reporter.format_timeline(activities, :unknown)
        expect(timeline.first[:period]).to eq('2025-01-10')
      end
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 'u1',
        generated_at: fixed_time.iso8601,
        summary: { total_actions: 2 }
      }
    end

    context 'when no filepath is provided' do
      it 'returns JSON data in the response' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to eq(true)
        expect(result[:data]).to be_a(String)
        parsed = JSON.parse(result[:data])
        expected = JSON.parse(JSON.pretty_generate(report))
        expect(parsed).to eq(expected)
      end
    end

    context 'when a filepath is provided' do
      it 'writes the JSON to the file and returns metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to eq(true)
          expect(result[:filepath]).to eq(path)
          expect(File.exist?(path)).to eq(true)
          content = File.read(path)
          expect(JSON.parse(content)).to eq(JSON.parse(JSON.pretty_generate(report)))
          expect(result[:size]).to eq(content.bytesize)
        end
      end
    end

    context 'when file writing fails' do
      it 'returns an error response' do
        allow(File).to receive(:write).and_raise(StandardError.new('boom'))
        result = reporter.export_to_json(report, '/tmp/whatever.json')
        expect(result[:success]).to eq(false)
        expect(result[:error]).to eq('boom')
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with three users of varying scores' do
      let(:user_ids) { %w[u1 u2 u3] }

      before do
        # Activities can be empty; only score and stats fields used here
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{
                                                                                   'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'a'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{
                                                                                   'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'b'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([{
                                                                                   'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'c'
                                                                                 }])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({ total_actions: 10, unique_actions: 3,
                                                                                  action_counts: {}, first_activity: fixed_time.iso8601, last_activity: fixed_time.iso8601, most_frequent: 'a' })
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({ total_actions: 20, unique_actions: 5,
                                                                                  action_counts: {}, first_activity: fixed_time.iso8601, last_activity: fixed_time.iso8601, most_frequent: 'b' })
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return({ total_actions: 5, unique_actions: 2,
                                                                                  action_counts: {}, first_activity: fixed_time.iso8601, last_activity: fixed_time.iso8601, most_frequent: 'c' })

        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2025-01-01T00:00:00Z',
                                                              'action' => 'a' }]).and_return(50.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2025-01-01T00:00:00Z',
                                                              'action' => 'b' }]).and_return(75.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2025-01-01T00:00:00Z',
                                                              'action' => 'c' }]).and_return(25.0)
      end

      it 'returns sorted comparisons, top user and average score' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[u2 u1 u3])
        expect(result[:comparisons].map { |c| c[:total_actions] }).to eq([20, 10, 5])
        expect(result[:comparisons].map { |c| c[:engagement_score] }).to eq([75.0, 50.0, 25.0])
        expect(result[:comparisons].map { |c| c[:most_frequent_action] }).to eq(%w[b a c])
        expect(result[:top_user]).to eq('u2')
        expect(result[:average_score]).to eq(((75.0 + 50.0 + 25.0) / 3.0).round(2))
      end
    end

    context 'with tie scores maintains input order for ties' do
      let(:user_ids) { %w[a b] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with('a').and_return([{
                                                                                  'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'x'
                                                                                }])
        allow(reporter).to receive(:fetch_user_activities).with('b').and_return([{
                                                                                  'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'y'
                                                                                }])

        allow(reporter).to receive(:fetch_activity_stats).with('a').and_return({ total_actions: 1, unique_actions: 1,
                                                                                 action_counts: {}, first_activity: fixed_time.iso8601, last_activity: fixed_time.iso8601, most_frequent: 'x' })
        allow(reporter).to receive(:fetch_activity_stats).with('b').and_return({ total_actions: 1, unique_actions: 1,
                                                                                 action_counts: {}, first_activity: fixed_time.iso8601, last_activity: fixed_time.iso8601, most_frequent: 'y' })

        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2025-01-01T00:00:00Z',
                                                              'action' => 'x' }]).and_return(50.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2025-01-01T00:00:00Z',
                                                              'action' => 'y' }]).and_return(50.0)
      end

      it 'keeps original order for equal scores' do
        result = reporter.compare_users(user_ids)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[a b])
        expect(result[:top_user]).to eq('a')
        expect(result[:average_score]).to eq(50.0)
      end
    end
  end
end
