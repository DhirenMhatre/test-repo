require 'spec_helper'
require 'tmpdir'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:go_url) { 'http://go.example:8080' }
  let(:py_url) { 'http://py.example:8081' }
  let(:reporter) { described_class.new(go_service_url: go_url, python_service_url: py_url) }
  let(:fixed_time) { Time.utc(2025, 1, 10, 12, 0, 0) }

  before do
    allow(Time).to receive(:now).and_return(fixed_time)
  end

  describe '#initialize' do
    it 'sets provided service URLs on the instance' do
      expect(reporter.instance_variable_get(:@go_service_url)).to eq(go_url)
      expect(reporter.instance_variable_get(:@python_service_url)).to eq(py_url)
    end

    it 'uses default service URLs when not provided' do
      default_reporter = described_class.new
      expect(default_reporter.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
      expect(default_reporter.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
    end
  end

  describe '#generate_report' do
    let(:user_id) { 'user-123' }

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report' do
        result = reporter.generate_report(user_id)
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with activities and computed data' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-02T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-02T11:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-03T09:00:00Z', 'action' => 'login' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 2,
          action_counts: { 'login' => 2, 'click' => 1 },
          first_activity: '2025-01-02T10:15:00Z',
          last_activity: '2025-01-03T09:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'streak', 'description' => 'Daily logins', 'confidence' => 0.8 },
          { 'pattern_type' => 'session', 'description' => 'Long sessions', 'confidence' => 0.6 }
        ]
      end

      let(:anomalies) do
        ['outlier-1']
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(78.5)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a comprehensive report' do
        result = reporter.generate_report(user_id, group_by: :day)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(fixed_time.iso8601)

        expect(result[:summary][:total_actions]).to eq(3)
        expect(result[:summary][:unique_actions]).to eq(2)
        expect(result[:summary][:engagement_score]).to eq(78.5)
        expect(result[:summary][:first_activity]).to eq('2025-01-02T10:15:00Z')
        expect(result[:summary][:last_activity]).to eq('2025-01-03T09:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'login' => 2, 'click' => 1 })

        expect(result[:patterns]).to eq(
          [
            { type: 'streak', description: 'Daily logins', confidence: 0.8 },
            { type: 'session', description: 'Long sessions', confidence: 0.6 }
          ]
        )

        expect(result[:anomalies]).to eq(['outlier-1'])

        expect(result[:timeline].map do |t|
          t[:period]
        end).to eq(%w[2025-01-02 2025-01-03])

        day_1 = result[:timeline].find do |t|
          t[:period] == '2025-01-02'
        end
        expect(day_1[:total_actions]).to eq(2)
        expect(day_1[:actions]).to eq({ 'login' => 1, 'click' => 1 })
        expect(day_1[:first_timestamp]).to eq('2025-01-02T10:15:00Z')
        expect(day_1[:last_timestamp]).to eq('2025-01-02T11:00:00Z')

        day_2 = result[:timeline].find do |t|
          t[:period] == '2025-01-03'
        end
        expect(day_2[:total_actions]).to eq(1)
        expect(day_2[:actions]).to eq({ 'login' => 1 })

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Low engagement - consider re-engagement strategies').or include('Moderately engaged user with regular activity')
        expect(result[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(result[:insights]).not_to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).not_to include('Clear behavioral patterns detected')
        expect(result[:insights]).not_to include('Power user - high volume of activities')
      end
    end

    context 'insights cover multiple conditions' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'a' }
        ]
      end

      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 12,
          action_counts: { 'a' => 150 },
          first_activity: '2025-01-01T00:00:00Z',
          last_activity: '2025-01-10T00:00:00Z',
          most_frequent: 'a'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'p1', 'description' => 'd1', 'confidence' => 0.9 },
          { 'pattern_type' => 'p2', 'description' => 'd2', 'confidence' => 0.7 },
          { 'pattern_type' => 'p3', 'description' => 'd3', 'confidence' => 0.6 }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(20.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([])
      end

      it 'includes diversity, patterns, and power-user insights' do
        result = reporter.generate_report(user_id)
        insights = result[:insights]

        expect(insights).to include('Low engagement - consider re-engagement strategies')
        expect(insights).to include('Diverse activity profile across multiple action types')
        expect(insights).to include('Clear behavioral patterns detected')
        expect(insights).to include('Power user - high volume of activities')
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities array is empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([])).to eq([])
      end
    end

    context 'with invalid timestamps' do
      it 'groups using current time when timestamp parsing fails' do
        activities = [
          { 'timestamp' => 'not-a-time', 'action' => 'login' },
          { 'timestamp' => 'also-bad', 'action' => 'click' }
        ]

        result = reporter.format_timeline(activities)
        expect(result.length).to eq(1)
        expect(result.first[:period]).to eq(fixed_time.strftime('%Y-%m-%d'))
        expect(result.first[:total_actions]).to eq(2)
        expect(result.first[:actions]).to eq({ 'login' => 1, 'click' => 1 })
      end
    end

    context 'grouped by hour' do
      it 'aggregates into hourly buckets' do
        activities = [
          { 'timestamp' => '2025-01-02T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-02T10:45:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-02T11:05:00Z', 'action' => 'click' }
        ]

        result = reporter.format_timeline(activities, :hour)
        periods = result.map do |e|
          e[:period]
        end

        expect(periods).to eq(['2025-01-02 10:00', '2025-01-02 11:00'])

        hour_10 = result.find do |e|
          e[:period] == '2025-01-02 10:00'
        end
        expect(hour_10[:total_actions]).to eq(2)
        expect(hour_10[:actions]).to eq({ 'login' => 2 })

        hour_11 = result.find do |e|
          e[:period] == '2025-01-02 11:00'
        end
        expect(hour_11[:total_actions]).to eq(1)
        expect(hour_11[:actions]).to eq({ 'click' => 1 })
      end
    end

    context 'grouped by week' do
      it 'aggregates into ISO week buckets' do
        activities = [
          { 'timestamp' => '2025-01-02T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-03T12:00:00Z', 'action' => 'click' }
        ]

        result = reporter.format_timeline(activities, :week)
        expect(result.length).to eq(1)
        expect(result.first[:period]).to match(/\A2025-W\d{2}\z/)
        expect(result.first[:total_actions]).to eq(2)
        expect(result.first[:actions]).to eq({ 'login' => 1, 'click' => 1 })
      end
    end

    context 'grouped by month' do
      it 'aggregates into monthly buckets' do
        activities = [
          { 'timestamp' => '2025-01-31T23:59:59Z', 'action' => 'a' },
          { 'timestamp' => '2025-02-01T00:00:00Z', 'action' => 'b' }
        ]

        result = reporter.format_timeline(activities, :month)
        periods = result.map do |e|
          e[:period]
        end

        expect(periods).to eq(%w[2025-01 2025-02])
        jan = result.find do |e|
          e[:period] == '2025-01'
        end
        feb = result.find do |e|
          e[:period] == '2025-02'
        end
        expect(jan[:total_actions]).to eq(1)
        expect(jan[:actions]).to eq({ 'a' => 1 })
        expect(feb[:total_actions]).to eq(1)
        expect(feb[:actions]).to eq({ 'b' => 1 })
      end
    end

    context 'with unknown grouping' do
      it 'defaults to day grouping' do
        activities = [
          { 'timestamp' => '2025-03-01T08:00:00Z', 'action' => 'x' }
        ]

        result = reporter.format_timeline(activities, :unknown)
        expect(result.length).to eq(1)
        expect(result.first[:period]).to eq('2025-03-01')
      end
    end
  end

  describe '#export_to_json' do
    let(:simple_report) do
      {
        user_id: 'u-1',
        generated_at: fixed_time.iso8601,
        summary: { total_actions: 1 }
      }
    end

    context 'when filepath is not provided' do
      it 'returns a success result with JSON data' do
        result = reporter.export_to_json(simple_report)
        expect(result[:success]).to be true
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq('u-1')
        expect(parsed['summary']['total_actions']).to eq(1)
      end
    end

    context 'when filepath is provided' do
      it 'writes the JSON to disk and returns metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(simple_report, path)

          expect(result[:success]).to be true
          expect(result[:filepath]).to eq(path)
          expect(File.exist?(path)).to be true

          contents = File.read(path)
          expect(contents).to eq(JSON.pretty_generate(simple_report))
          expect(result[:size]).to eq(contents.bytesize)
        end
      end
    end

    context 'when writing to disk fails' do
      it 'returns an error result' do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        result = reporter.export_to_json(simple_report, '/nope/path.json')
        expect(result[:success]).to be false
        expect(result[:error]).to eq('disk full')
      end
    end

    context 'when serialization fails' do
      it 'returns an error result' do
        allow(JSON).to receive(:pretty_generate).and_raise(StandardError.new('boom'))
        result = reporter.export_to_json(simple_report)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('boom')
      end
    end
  end

  describe '#compare_users' do
    context 'when less than two user IDs are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with two users' do
      let(:user_a) { 'a' }
      let(:user_b) { 'b' }
      let(:acts_a) do
        [
          { 'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'x' }
        ]
      end
      let(:acts_b) do
        [
          { 'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'y' },
          { 'timestamp' => '2025-01-02T00:00:00Z', 'action' => 'y' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_a).and_return(acts_a)
        allow(reporter).to receive(:fetch_user_activities).with(user_b).and_return(acts_b)

        allow(reporter).to receive(:fetch_activity_stats).with(user_a).and_return(
          {
            total_actions: 5,
            unique_actions: 2,
            action_counts: { 'x' => 5 },
            first_activity: '2025-01-01T00:00:00Z',
            last_activity: '2025-01-05T00:00:00Z',
            most_frequent: 'x'
          }
        )

        allow(reporter).to receive(:fetch_activity_stats).with(user_b).and_return(
          {
            total_actions: 12,
            unique_actions: 3,
            action_counts: { 'y' => 12 },
            first_activity: '2025-01-01T00:00:00Z',
            last_activity: '2025-01-12T00:00:00Z',
            most_frequent: 'y'
          }
        )

        allow(reporter).to receive(:fetch_user_score).with(acts_a).and_return(30.0)
        allow(reporter).to receive(:fetch_user_score).with(acts_b).and_return(80.2)
      end

      it 'compares users and sorts by engagement score' do
        result = reporter.compare_users([user_a, user_b])

        expect(result[:total_users]).to eq(2)
        expect(result[:comparisons].length).to eq(2)

        top = result[:comparisons].first
        expect(top[:user_id]).to eq(user_b)
        expect(top[:engagement_score]).to eq(80.2)
        expect(top[:most_frequent_action]).to eq('y')

        lower = result[:comparisons].last
        expect(lower[:user_id]).to eq(user_a)
        expect(lower[:engagement_score]).to eq(30.0)
        expect(lower[:most_frequent_action]).to eq('x')

        expect(result[:top_user]).to eq(user_b)
        expect(result[:average_score]).to eq(55.1)
      end
    end
  end
end
