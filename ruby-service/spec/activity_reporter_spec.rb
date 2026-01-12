require 'spec_helper'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:go_service_url) { 'http://localhost:8080' }
  let(:python_service_url) { 'http://localhost:8081' }
  let(:reporter) do
    described_class.new(
      go_service_url: go_service_url,
      python_service_url: python_service_url
    )
  end

  let(:user_id) { 'user-123' }

  describe '#initialize' do
    context 'with default arguments' do
      let(:reporter_default) { described_class.new }

      it 'sets default go_service_url' do
        expect(reporter_default.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
      end

      it 'sets default python_service_url' do
        expect(reporter_default.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
      end
    end

    context 'with custom arguments' do
      let(:custom_go_url) { 'http://go.example.com' }
      let(:custom_python_url) { 'http://py.example.com' }
      let(:reporter_custom) do
        described_class.new(
          go_service_url: custom_go_url,
          python_service_url: custom_python_url
        )
      end

      it 'sets custom go_service_url' do
        expect(reporter_custom.instance_variable_get(:@go_service_url)).to eq(custom_go_url)
      end

      it 'sets custom python_service_url' do
        expect(reporter_custom.instance_variable_get(:@python_service_url)).to eq(custom_python_url)
      end
    end
  end

  describe '#generate_report' do
    let(:activities) do
      [
        { 'timestamp' => '2024-01-01T10:00:00Z', 'action' => 'login' },
        { 'timestamp' => '2024-01-01T11:00:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-01-02T09:30:00Z', 'action' => 'logout' }
      ]
    end

    let(:stats) do
      {
        total_actions: 3,
        unique_actions: 3,
        action_counts: { 'login' => 1, 'click' => 1, 'logout' => 1 },
        first_activity: '2024-01-01T10:00:00Z',
        last_activity: '2024-01-02T09:30:00Z',
        most_frequent: 'login'
      }
    end

    let(:patterns) do
      [
        { 'pattern_type' => 'daily', 'description' => 'Logs in every day', 'confidence' => 0.9 },
        { 'pattern_type' => 'morning', 'description' => 'Active in the morning', 'confidence' => 0.8 }
      ]
    end

    let(:user_score) { 80.5 }
    let(:anomalies) do
      [
        { 'timestamp' => '2024-01-03T03:00:00Z', 'action' => 'login', 'reason' => 'unusual time' }
      ]
    end

    before do
      allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
      allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
      allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
      allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
      allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      allow(Time).to receive(:now).and_return(Time.parse('2024-01-10T12:00:00Z'))
    end

    context 'when activities exist' do
      it 'returns a report hash with expected top-level keys' do
        report = reporter.generate_report(user_id)

        expect(report).to be_a(Hash)
        expect(report[:user_id]).to eq(user_id)
        expect(report[:generated_at]).to eq('2024-01-10T12:00:00Z')
        expect(report).to have_key(:summary)
        expect(report).to have_key(:action_breakdown)
        expect(report).to have_key(:patterns)
        expect(report).to have_key(:anomalies)
        expect(report).to have_key(:timeline)
        expect(report).to have_key(:insights)
      end

      it 'includes correct summary data' do
        report = reporter.generate_report(user_id)
        summary = report[:summary]

        expect(summary[:total_actions]).to eq(3)
        expect(summary[:unique_actions]).to eq(3)
        expect(summary[:engagement_score]).to eq(user_score)
        expect(summary[:first_activity]).to eq('2024-01-01T10:00:00Z')
        expect(summary[:last_activity]).to eq('2024-01-02T09:30:00Z')
      end

      it 'includes formatted patterns' do
        report = reporter.generate_report(user_id)
        formatted_patterns = report[:patterns]

        expect(formatted_patterns.length).to eq(2)
        expect(formatted_patterns.first).to eq(
          type: 'daily',
          description: 'Logs in every day',
          confidence: 0.9
        )
      end

      it 'includes anomalies as returned from fetch_anomalies' do
        report = reporter.generate_report(user_id)
        expect(report[:anomalies]).to eq(anomalies)
      end

      it 'builds a timeline grouped by default :day' do
        expect(reporter).to receive(:format_timeline).with(activities, :day).and_call_original
        report = reporter.generate_report(user_id)
        expect(report[:timeline]).to be_an(Array)
        expect(report[:timeline].map { |t| t[:period] }).to eq(%w[2024-01-01 2024-01-02])
      end

      it 'respects group_by option when provided' do
        expect(reporter).to receive(:format_timeline).with(activities, :hour).and_call_original
        report = reporter.generate_report(user_id, group_by: :hour)
        expect(report[:timeline].map do |t|
          t[:period]
        end).to include('2024-01-01 10:00', '2024-01-01 11:00', '2024-01-02 09:00')
      end

      it 'generates insights based on stats, patterns, score, and anomalies' do
        expect(reporter).to receive(:generate_insights).with(stats, patterns, user_score, anomalies).and_call_original
        report = reporter.generate_report(user_id)
        expect(report[:insights]).to be_an(Array)
        expect(report[:insights]).not_to be_empty
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
        expect(report[:generated_at]).to eq('2024-01-10T12:00:00Z')
      end

      it 'does not call other fetch methods' do
        expect(reporter).not_to receive(:fetch_activity_stats)
        expect(reporter).not_to receive(:fetch_activity_patterns)
        expect(reporter).not_to receive(:fetch_user_score)
        expect(reporter).not_to receive(:fetch_anomalies)

        reporter.generate_report(user_id)
      end
    end
  end

  describe '#format_timeline' do
    let(:activities) do
      [
        { 'timestamp' => '2024-01-02T10:15:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-01-01T09:00:00Z', 'action' => 'login' },
        { 'timestamp' => '2024-01-01T10:00:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-01-08T12:00:00Z', 'action' => 'logout' }
      ]
    end

    context 'when activities array is empty' do
      it 'returns an empty array' do
        result = reporter.format_timeline([])
        expect(result).to eq([])
      end
    end

    context 'when grouping by day' do
      it 'groups activities by date and sorts by period' do
        result = reporter.format_timeline(activities, :day)

        expect(result.length).to eq(3)
        expect(result.map { |r| r[:period] }).to eq(%w[2024-01-01 2024-01-02 2024-01-08])

        day1 = result.find { |r| r[:period] == '2024-01-01' }
        expect(day1[:total_actions]).to eq(2)
        expect(day1[:actions]).to eq('login' => 1, 'click' => 1)
        expect(day1[:first_timestamp]).to eq('2024-01-01T09:00:00Z')
        expect(day1[:last_timestamp]).to eq('2024-01-01T10:00:00Z')
      end
    end

    context 'when grouping by hour' do
      it 'groups activities by hour' do
        result = reporter.format_timeline(activities, :hour)
        periods = result.map { |r| r[:period] }

        expect(periods).to include('2024-01-01 09:00')
        expect(periods).to include('2024-01-01 10:00')
        expect(periods).to include('2024-01-02 10:00')
        expect(periods).to include('2024-01-08 12:00')
      end
    end

    context 'when grouping by week' do
      it 'groups activities by ISO week' do
        result = reporter.format_timeline(activities, :week)
        periods = result.map { |r| r[:period] }

        expect(periods).to include('2024-W01')
        expect(periods).to include('2024-W02')
      end
    end

    context 'when grouping by month' do
      it 'groups activities by month' do
        result = reporter.format_timeline(activities, :month)
        expect(result.length).to eq(1)
        expect(result.first[:period]).to eq('2024-01')
        expect(result.first[:total_actions]).to eq(4)
      end
    end

    context 'when grouping by unknown key' do
      it 'defaults to grouping by day' do
        result = reporter.format_timeline(activities, :unknown)
        expect(result.map { |r| r[:period] }).to eq(%w[2024-01-01 2024-01-02 2024-01-08])
      end
    end

    context 'when timestamps are invalid' do
      let(:now_time) { Time.parse('2024-01-10T00:00:00Z') }
      let(:activities_with_invalid) do
        [
          { 'timestamp' => 'invalid-timestamp', 'action' => 'login' }
        ]
      end

      before do
        allow(Time).to receive(:now).and_return(now_time)
      end

      it 'uses current time for invalid timestamps via parse_timestamp' do
        result = reporter.format_timeline(activities_with_invalid, :day)
        expect(result.length).to eq(1)
        expect(result.first[:period]).to eq(now_time.strftime('%Y-%m-%d'))
      end
    end
  end

  describe '#export_to_json' do
    let(:report_hash) do
      {
        user_id: user_id,
        summary: { total_actions: 5 }
      }
    end

    before do
      allow(JSON).to receive(:pretty_generate).and_call_original
    end

    context 'when filepath is not provided' do
      it 'returns success with data key containing JSON string' do
        result = reporter.export_to_json(report_hash)

        expect(result[:success]).to eq(true)
        expect(result[:data]).to be_a(String)
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq(user_id)
        expect(parsed['summary']['total_actions']).to eq(5)
      end
    end

    context 'when filepath is provided' do
      let(:filepath) { 'tmp/test_report.json' }

      before do
        allow(File).to receive(:write).and_return(100)
      end

      it 'writes JSON to the given file and returns metadata' do
        result = reporter.export_to_json(report_hash, filepath)

        expect(File).to have_received(:write).with(filepath, kind_of(String))
        expect(result[:success]).to eq(true)
        expect(result[:filepath]).to eq(filepath)
        expect(result[:size]).to be_a(Integer)
      end
    end

    context 'when an error occurs during file write' do
      let(:filepath) { 'tmp/test_report_error.json' }

      before do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      end

      it 'returns a failure hash with error message' do
        result = reporter.export_to_json(report_hash, filepath)

        expect(result[:success]).to eq(false)
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    let(:user_ids) { %w[user1 user2 user3] }

    let(:activities_user1) do
      [
        { 'timestamp' => '2024-01-01T10:00:00Z', 'action' => 'login' }
      ]
    end

    let(:activities_user2) do
      [
        { 'timestamp' => '2024-01-01T11:00:00Z', 'action' => 'login' },
        { 'timestamp' => '2024-01-01T12:00:00Z', 'action' => 'click' }
      ]
    end

    let(:activities_user3) do
      [
        { 'timestamp' => '2024-01-02T09:00:00Z', 'action' => 'login' },
        { 'timestamp' => '2024-01-02T10:00:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-01-02T11:00:00Z', 'action' => 'logout' }
      ]
    end

    let(:stats_user1) do
      {
        total_actions: 1,
        unique_actions: 1,
        action_counts: { 'login' => 1 },
        first_activity: '2024-01-01T10:00:00Z',
        last_activity: '2024-01-01T10:00:00Z',
        most_frequent: 'login'
      }
    end

    let(:stats_user2) do
      {
        total_actions: 2,
        unique_actions: 2,
        action_counts: { 'login' => 1, 'click' => 1 },
        first_activity: '2024-01-01T11:00:00Z',
        last_activity: '2024-01-01T12:00:00Z',
        most_frequent: 'login'
      }
    end

    let(:stats_user3) do
      {
        total_actions: 3,
        unique_actions: 3,
        action_counts: { 'login' => 1, 'click' => 1, 'logout' => 1 },
        first_activity: '2024-01-02T09:00:00Z',
        last_activity: '2024-01-02T11:00:00Z',
        most_frequent: 'login'
      }
    end

    before do
      allow_any_instance_of(ActivityReporter).to receive(:fetch_user_activities).with('user1').and_return(activities_user1)
      allow_any_instance_of(ActivityReporter).to receive(:fetch_user_activities).with('user2').and_return(activities_user2)
      allow_any_instance_of(ActivityReporter).to receive(:fetch_user_activities).with('user3').and_return(activities_user3)

      allow_any_instance_of(ActivityReporter).to receive(:fetch_activity_stats).with('user1').and_return(stats_user1)
      allow_any_instance_of(ActivityReporter).to receive(:fetch_activity_stats).with('user2').and_return(stats_user2)
      allow_any_instance_of(ActivityReporter).to receive(:fetch_activity_stats).with('user3').and_return(stats_user3)

      allow_any_instance_of(ActivityReporter).to receive(:fetch_user_score).with(activities_user1).and_return(10.0)
      allow_any_instance_of(ActivityReporter).to receive(:fetch_user_score).with(activities_user2).and_return(50.0)
      allow_any_instance_of(ActivityReporter).to receive(:fetch_user_score).with(activities_user3).and_return(90.0)
    end

    context 'when fewer than 2 users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])

        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'when multiple users are provided' do
      it 'returns comparison data for each user' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].length).to eq(3)

        comparison_user1 = result[:comparisons].find { |c| c[:user_id] == 'user1' }
        expect(comparison_user1[:total_actions]).to eq(1)
        expect(comparison_user1[:engagement_score]).to eq(10.0)
        expect(comparison_user1[:most_frequent_action]).to eq('login')
      end

      it 'sorts comparisons by engagement_score descending' do
        result = reporter.compare_users(user_ids)
        scores = result[:comparisons].map { |c| c[:engagement_score] }

        expect(scores).to eq(scores.sort.reverse)
      end

      it 'sets top_user to the user with highest engagement_score' do
        result = reporter.compare_users(user_ids)
        expect(result[:top_user]).to eq('user3')
      end

      it 'calculates average_score correctly' do
        result = reporter.compare_users(user_ids)
        expect(result[:average_score]).to eq(((10.0 + 50.0 + 90.0) / 3.0).round(2))
      end
    end

    context 'when engagement scores are equal' do
      before do
        allow_any_instance_of(ActivityReporter).to receive(:fetch_user_score).with(activities_user1).and_return(50.0)
        allow_any_instance_of(ActivityReporter).to receive(:fetch_user_score).with(activities_user2).and_return(50.0)
        allow_any_instance_of(ActivityReporter).to receive(:fetch_user_score).with(activities_user3).and_return(50.0)
      end

      it 'maintains insertion order among equal scores' do
        result = reporter.compare_users(user_ids)
        ordered_ids = result[:comparisons].map { |c| c[:user_id] }
        expect(ordered_ids).to eq(user_ids)
      end
    end
  end

  describe '#parse_timestamp' do
    it 'parses a valid ISO8601 timestamp string' do
      time = reporter.send(:parse_timestamp, '2024-01-01T10:00:00Z')
      expect(time).to be_a(Time)
      expect(time.utc.iso8601).to eq('2024-01-01T10:00:00Z')
    end

    it 'returns current time when timestamp is invalid' do
      now_time = Time.parse('2024-01-10T00:00:00Z')
      allow(Time).to receive(:now).and_return(now_time)

      time = reporter.send(:parse_timestamp, 'invalid')
      expect(time).to eq(now_time)
    end
  end

  describe '#format_pattern' do
    let(:pattern) do
      {
        'pattern_type' => 'daily',
        'description' => 'Daily login',
        'confidence' => 0.95
      }
    end

    it 'formats a pattern hash into expected structure' do
      result = reporter.send(:format_pattern, pattern)

      expect(result).to eq(
        type: 'daily',
        description: 'Daily login',
        confidence: 0.95
      )
    end
  end

  describe '#generate_insights' do
    let(:stats) do
      {
        total_actions: total_actions,
        unique_actions: unique_actions,
        action_counts: {},
        first_activity: '2024-01-01T10:00:00Z',
        last_activity: '2024-01-02T10:00:00Z',
        most_frequent: 'login'
      }
    end

    let(:patterns) { Array.new(pattern_count) { { 'pattern_type' => 'x' } } }
    let(:anomalies) { Array.new(anomaly_count) { { 'a' => 1 } } }

    context 'when user_score is high' do
      let(:total_actions) { 150 }
      let(:unique_actions) { 12 }
      let(:pattern_count) { 3 }
      let(:anomaly_count) { 2 }
      let(:user_score) { 80.0 }

      it 'includes multiple positive insights and anomaly notice' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Highly engaged user with strong activity patterns')
        expect(insights).to include('Diverse activity profile across multiple action types')
        expect(insights).to include('Clear behavioral patterns detected')
        expect(insights).to include('2 anomalous activities detected - review recommended')
        expect(insights).to include('Power user - high volume of activities')
      end
    end

    context 'when user_score is moderate' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 0 }
      let(:user_score) { 60.0 }

      it 'includes moderate engagement insight only' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Moderately engaged user with regular activity')
        expect(insights.any? { |i| i.include?('Low engagement') }).to eq(false)
        expect(insights.any? { |i| i.include?('Highly engaged') }).to eq(false)
      end
    end

    context 'when user_score is low' do
      let(:total_actions) { 10 }
      let(:unique_actions) { 2 }
      let(:pattern_count) { 0 }
      let(:anomaly_count) { 0 }
      let(:user_score) { 20.0 }

      it 'includes low engagement insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Low engagement - consider re-engagement strategies')
      end
    end

    context 'when there are no anomalies, few patterns, and low diversity' do
      let(:total_actions) { 101 }
      let(:unique_actions) { 3 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 0 }
      let(:user_score) { 76.0 }

      it 'includes power user and high engagement but not diversity or pattern insights' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Highly engaged user with strong activity patterns')
        expect(insights).to include('Power user - high volume of activities')
        expect(insights.any? { |i| i.include?('Diverse activity profile') }).to eq(false)
        expect(insights.any? { |i| i.include?('Clear behavioral patterns detected') }).to eq(false)
        expect(insights.any? { |i| i.include?('anomalous activities detected') }).to eq(false)
      end
    end
  end

  describe '#error_report' do
    it 'returns an error hash with message and generated_at' do
      allow(Time).to receive(:now).and_return(Time.parse('2024-01-10T12:00:00Z'))

      result = reporter.send(:error_report, 'Something went wrong')

      expect(result[:error]).to eq(true)
      expect(result[:message]).to eq('Something went wrong')
      expect(result[:generated_at]).to eq('2024-01-10T12:00:00Z')
    end
  end
end
