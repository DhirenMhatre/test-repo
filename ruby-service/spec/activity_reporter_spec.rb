require 'spec_helper'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:go_service_url) do
    'http://go-service.test'
  end

  let(:python_service_url) do
    'http://python-service.test'
  end

  let(:reporter) do
    described_class.new(
      go_service_url: go_service_url,
      python_service_url: python_service_url
    )
  end

  describe '#initialize' do
    it 'sets the service URLs from arguments' do
      instance = described_class.new(
        go_service_url: 'http://custom-go',
        python_service_url: 'http://custom-python'
      )

      expect(instance.instance_variable_get(:@go_service_url)).to eq('http://custom-go')
      expect(instance.instance_variable_get(:@python_service_url)).to eq('http://custom-python')
    end

    it 'uses default URLs when none are provided' do
      instance = described_class.new

      expect(instance.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
      expect(instance.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
    end
  end

  describe '#generate_report' do
    let(:user_id) do
      123
    end

    let(:activities) do
      [
        { 'timestamp' => '2024-01-01T10:00:00Z', 'action' => 'login' },
        { 'timestamp' => '2024-01-01T11:00:00Z', 'action' => 'view_page' },
        { 'timestamp' => '2024-01-02T09:30:00Z', 'action' => 'purchase' }
      ]
    end

    let(:stats) do
      {
        total_actions: 3,
        unique_actions: 3,
        action_counts: { 'login' => 1, 'view_page' => 1, 'purchase' => 1 },
        first_activity: '2024-01-01T10:00:00Z',
        last_activity: '2024-01-02T09:30:00Z',
        most_frequent: 'login'
      }
    end

    let(:patterns) do
      [
        { 'pattern_type' => 'daily', 'description' => 'Active in mornings', 'confidence' => 0.9 },
        { 'pattern_type' => 'weekly', 'description' => 'More active on weekdays', 'confidence' => 0.8 }
      ]
    end

    let(:user_score) do
      80.0
    end

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
    end

    context 'when activities exist' do
      it 'returns a structured report hash with expected keys' do
        report = reporter.generate_report(user_id)

        expect(report[:user_id]).to eq(user_id)
        expect(report[:generated_at]).to be_a(String)

        expect(report[:summary]).to include(
          total_actions: stats[:total_actions],
          unique_actions: stats[:unique_actions],
          engagement_score: user_score,
          first_activity: stats[:first_activity],
          last_activity: stats[:last_activity]
        )

        expect(report[:action_breakdown]).to eq(stats[:action_counts])

        expect(report[:patterns]).to all(include(:type, :description, :confidence))
        expect(report[:patterns].map { |p| p[:type] }).to match_array(%w[daily weekly])

        expect(report[:anomalies]).to eq(anomalies)

        expect(report[:timeline]).to be_an(Array)
        expect(report[:insights]).to be_an(Array)
        expect(report[:insights]).not_to be_empty
      end

      it 'groups timeline by default by day' do
        report = reporter.generate_report(user_id)

        periods = report[:timeline].map { |t| t[:period] }
        expect(periods).to include('2024-01-01', '2024-01-02')
      end

      it 'respects the group_by option for timeline' do
        report = reporter.generate_report(user_id, group_by: :month)

        periods = report[:timeline].map { |t| t[:period] }
        expect(periods).to all(eq('2024-01'))
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
        expect(report[:generated_at]).to be_a(String)
      end
    end
  end

  describe '#format_timeline' do
    let(:activities) do
      [
        { 'timestamp' => '2024-01-01T10:15:00Z', 'action' => 'login' },
        { 'timestamp' => '2024-01-01T10:45:00Z', 'action' => 'view_page' },
        { 'timestamp' => '2024-01-01T11:05:00Z', 'action' => 'purchase' },
        { 'timestamp' => '2024-01-02T09:00:00Z', 'action' => 'login' }
      ]
    end

    context 'when activities array is empty' do
      it 'returns an empty array' do
        result = reporter.format_timeline([])

        expect(result).to eq([])
      end
    end

    context 'when grouping by hour' do
      it 'groups activities into hourly buckets' do
        result = reporter.format_timeline(activities, :hour)

        periods = result.map { |r| r[:period] }
        expect(periods).to include('2024-01-01 10:00', '2024-01-01 11:00', '2024-01-02 09:00')

        ten_am_bucket = result.find { |r| r[:period] == '2024-01-01 10:00' }
        expect(ten_am_bucket[:total_actions]).to eq(2)
        expect(ten_am_bucket[:actions]).to eq('login' => 1, 'view_page' => 1)
      end
    end

    context 'when grouping by day' do
      it 'groups activities into daily buckets' do
        result = reporter.format_timeline(activities, :day)

        expect(result.size).to eq(2)

        day_bucket = result.find { |r| r[:period] == '2024-01-01' }
        expect(day_bucket[:total_actions]).to eq(3)
        expect(day_bucket[:actions]['login']).to eq(1)
        expect(day_bucket[:actions]['view_page']).to eq(1)
        expect(day_bucket[:actions]['purchase']).to eq(1)
      end
    end

    context 'when grouping by week' do
      it 'groups activities into weekly buckets' do
        result = reporter.format_timeline(activities, :week)

        expect(result.size).to eq(1)
        expect(result.first[:period]).to match(/\A2024-W\d{2}\z/)
        expect(result.first[:total_actions]).to eq(4)
      end
    end

    context 'when grouping by month' do
      it 'groups activities into monthly buckets' do
        result = reporter.format_timeline(activities, :month)

        expect(result.size).to eq(1)
        expect(result.first[:period]).to eq('2024-01')
        expect(result.first[:total_actions]).to eq(4)
      end
    end

    context 'when grouping by an unknown key' do
      it 'defaults to grouping by day' do
        result = reporter.format_timeline(activities, :unknown)

        expect(result.map { |r| r[:period] }).to include('2024-01-01', '2024-01-02')
      end
    end

    context 'ordering' do
      it 'sorts the timeline entries by period' do
        shuffled = activities.shuffle
        result = reporter.format_timeline(shuffled, :day)

        periods = result.map { |r| r[:period] }
        expect(periods).to eq(periods.sort)
      end
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 1,
        summary: { total_actions: 5 }
      }
    end

    context 'when filepath is not provided' do
      it 'returns success and JSON data' do
        result = reporter.export_to_json(report)

        expect(result[:success]).to eq(true)
        expect(result[:data]).to be_a(String)

        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq(1)
        expect(parsed['summary']['total_actions']).to eq(5)
      end
    end

    context 'when filepath is provided' do
      let(:filepath) do
        'tmp/test_report.json'
      end

      before do
        allow(File).to receive(:write).and_call_original
      end

      after do
        File.delete(filepath) if File.exist?(filepath)
      end

      it 'writes the file and returns metadata' do
        result = reporter.export_to_json(report, filepath)

        expect(File).to have_received(:write).with(filepath, kind_of(String))
        expect(result[:success]).to eq(true)
        expect(result[:filepath]).to eq(filepath)
        expect(result[:size]).to be > 0
      end
    end

    context 'when an error occurs during file write' do
      let(:filepath) do
        'tmp/failing_report.json'
      end

      before do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      end

      it 'returns a failure hash with error message' do
        result = reporter.export_to_json(report, filepath)

        expect(result[:success]).to eq(false)
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    let(:user_ids) do
      [1, 2, 3]
    end

    let(:activities_user1) do
      [{ 'timestamp' => '2024-01-01T10:00:00Z', 'action' => 'login' }]
    end

    let(:activities_user2) do
      [{ 'timestamp' => '2024-01-01T11:00:00Z', 'action' => 'view_page' }]
    end

    let(:activities_user3) do
      [{ 'timestamp' => '2024-01-01T12:00:00Z', 'action' => 'purchase' }]
    end

    let(:stats_user1) do
      {
        total_actions: 10,
        unique_actions: 3,
        action_counts: { 'login' => 5, 'view_page' => 3, 'purchase' => 2 },
        first_activity: '2024-01-01T10:00:00Z',
        last_activity: '2024-01-02T10:00:00Z',
        most_frequent: 'login'
      }
    end

    let(:stats_user2) do
      {
        total_actions: 5,
        unique_actions: 2,
        action_counts: { 'login' => 2, 'view_page' => 3 },
        first_activity: '2024-01-01T11:00:00Z',
        last_activity: '2024-01-02T11:00:00Z',
        most_frequent: 'view_page'
      }
    end

    let(:stats_user3) do
      {
        total_actions: 20,
        unique_actions: 4,
        action_counts: { 'login' => 10, 'view_page' => 5, 'purchase' => 5 },
        first_activity: '2024-01-01T12:00:00Z',
        last_activity: '2024-01-02T12:00:00Z',
        most_frequent: 'purchase'
      }
    end

    before do
      allow(reporter).to receive(:fetch_user_activities).with(1).and_return(activities_user1)
      allow(reporter).to receive(:fetch_user_activities).with(2).and_return(activities_user2)
      allow(reporter).to receive(:fetch_user_activities).with(3).and_return(activities_user3)

      allow(reporter).to receive(:fetch_activity_stats).with(1).and_return(stats_user1)
      allow(reporter).to receive(:fetch_activity_stats).with(2).and_return(stats_user2)
      allow(reporter).to receive(:fetch_activity_stats).with(3).and_return(stats_user3)

      allow(reporter).to receive(:fetch_user_score).with(activities_user1).and_return(60.0)
      allow(reporter).to receive(:fetch_user_score).with(activities_user2).and_return(40.0)
      allow(reporter).to receive(:fetch_user_score).with(activities_user3).and_return(90.0)
    end

    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users([1])

        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'when multiple users are provided' do
      it 'returns comparisons sorted by engagement_score descending' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].size).to eq(3)

        scores = result[:comparisons].map { |c| c[:engagement_score] }
        expect(scores).to eq(scores.sort.reverse)

        expect(result[:top_user]).to eq(3)

        expected_average = ((60.0 + 40.0 + 90.0) / 3.0).round(2)
        expect(result[:average_score]).to eq(expected_average)
      end

      it 'includes expected fields for each user comparison' do
        result = reporter.compare_users(user_ids)

        comparison = result[:comparisons].find { |c| c[:user_id] == 1 }

        expect(comparison[:total_actions]).to eq(stats_user1[:total_actions])
        expect(comparison[:engagement_score]).to eq(60.0)
        expect(comparison[:most_frequent_action]).to eq('login')
      end
    end
  end

  describe '#format_pattern' do
    let(:pattern) do
      {
        'pattern_type' => 'daily',
        'description' => 'Active every morning',
        'confidence' => 0.95
      }
    end

    it 'formats a raw pattern hash into a standardized structure' do
      result = reporter.send(:format_pattern, pattern)

      expect(result).to eq(
        type: 'daily',
        description: 'Active every morning',
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

    let(:patterns) do
      Array.new(pattern_count) do |i|
        { 'pattern_type' => "type#{i}", 'description' => "desc#{i}", 'confidence' => 0.5 }
      end
    end

    let(:anomalies) do
      Array.new(anomaly_count) do |i|
        { 'id' => i }
      end
    end

    let(:total_actions) do
      50
    end

    let(:unique_actions) do
      5
    end

    let(:pattern_count) do
      1
    end

    let(:anomaly_count) do
      0
    end

    context 'when user_score is high' do
      let(:user_score) do
        80
      end

      it 'includes a highly engaged insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Highly engaged user with strong activity patterns')
      end
    end

    context 'when user_score is moderate' do
      let(:user_score) do
        60
      end

      it 'includes a moderately engaged insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Moderately engaged user with regular activity')
      end
    end

    context 'when user_score is low' do
      let(:user_score) do
        40
      end

      it 'includes a low engagement insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Low engagement - consider re-engagement strategies')
      end
    end

    context 'when unique_actions is high' do
      let(:user_score) do
        40
      end

      let(:unique_actions) do
        11
      end

      it 'includes a diverse activity profile insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Diverse activity profile across multiple action types')
      end
    end

    context 'when many patterns exist' do
      let(:user_score) do
        40
      end

      let(:pattern_count) do
        3
      end

      it 'includes a clear behavioral patterns insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Clear behavioral patterns detected')
      end
    end

    context 'when anomalies exist' do
      let(:user_score) do
        40
      end

      let(:anomaly_count) do
        2
      end

      it 'includes an anomalies detected insight with count' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('2 anomalous activities detected - review recommended')
      end
    end

    context 'when total_actions is high' do
      let(:user_score) do
        40
      end

      let(:total_actions) do
        150
      end

      it 'includes a power user insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Power user - high volume of activities')
      end
    end
  end

  describe '#parse_timestamp' do
    context 'with a valid timestamp string' do
      let(:timestamp_str) do
        '2024-01-01T10:00:00Z'
      end

      it 'parses the timestamp into a Time object' do
        time = reporter.send(:parse_timestamp, timestamp_str)

        expect(time).to be_a(Time)
        expect(time.iso8601).to eq(Time.parse(timestamp_str).iso8601)
      end
    end

    context 'with an invalid timestamp string' do
      let(:timestamp_str) do
        'invalid-timestamp'
      end

      it 'returns the current time when parsing fails' do
        allow(Time).to receive(:now).and_return(Time.new(2024, 1, 1, 0, 0, 0, '+00:00'))

        time = reporter.send(:parse_timestamp, timestamp_str)

        expect(time).to eq(Time.now)
      end
    end
  end

  describe '#error_report' do
    let(:message) do
      'Something went wrong'
    end

    it 'returns an error hash with message and timestamp' do
      result = reporter.send(:error_report, message)

      expect(result[:error]).to eq(true)
      expect(result[:message]).to eq(message)
      expect(result[:generated_at]).to be_a(String)
    end
  end
end
