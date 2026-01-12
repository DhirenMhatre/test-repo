require 'spec_helper'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:go_service_url) { 'http://go-service:8080' }
  let(:python_service_url) { 'http://python-service:8081' }
  let(:reporter) do
    described_class.new(
      go_service_url: go_service_url,
      python_service_url: python_service_url
    )
  end

  describe '#initialize' do
    it 'sets the service URLs with provided values' do
      instance = described_class.new(
        go_service_url: 'http://custom-go',
        python_service_url: 'http://custom-python'
      )

      expect(instance.instance_variable_get(:@go_service_url)).to eq('http://custom-go')
      expect(instance.instance_variable_get(:@python_service_url)).to eq('http://custom-python')
    end

    it 'sets default service URLs when none are provided' do
      instance = described_class.new

      expect(instance.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
      expect(instance.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
    end
  end

  describe '#generate_report' do
    let(:user_id) { 123 }
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
        { 'pattern_type' => 'daily', 'description' => 'Logs in daily', 'confidence' => 0.9 },
        { 'pattern_type' => 'weekly', 'description' => 'Active on weekdays', 'confidence' => 0.8 }
      ]
    end
    let(:user_score) { 80.5 }
    let(:anomalies) do
      [
        { 'timestamp' => '2024-01-03T00:00:00Z', 'action' => 'suspicious_login' }
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
      it 'returns a detailed report hash with expected keys' do
        result = reporter.generate_report(user_id)

        expect(result).to be_a(Hash)
        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq('2024-01-10T12:00:00Z')
        expect(result[:summary]).to eq(
          total_actions: 3,
          unique_actions: 3,
          engagement_score: user_score,
          first_activity: '2024-01-01T10:00:00Z',
          last_activity: '2024-01-02T09:30:00Z'
        )
        expect(result[:action_breakdown]).to eq(stats[:action_counts])
        expect(result[:patterns]).to eq(
          [
            { type: 'daily', description: 'Logs in daily', confidence: 0.9 },
            { type: 'weekly', description: 'Active on weekdays', confidence: 0.8 }
          ]
        )
        expect(result[:anomalies]).to eq(anomalies)
        expect(result[:timeline]).to be_an(Array)
        expect(result[:insights]).to be_an(Array)
      end

      it 'uses the provided group_by option for timeline' do
        expect(reporter).to receive(:format_timeline).with(activities, :hour).and_call_original

        reporter.generate_report(user_id, group_by: :hour)
      end

      it 'defaults group_by to :day when not provided' do
        expect(reporter).to receive(:format_timeline).with(activities, :day).and_call_original

        reporter.generate_report(user_id)
      end
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
        allow(Time).to receive(:now).and_return(Time.parse('2024-01-10T12:00:00Z'))
      end

      it 'returns an error report' do
        result = reporter.generate_report(user_id)

        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq('2024-01-10T12:00:00Z')
      end
    end
  end

  describe '#format_timeline' do
    let(:activities) do
      [
        { 'timestamp' => '2024-01-01T10:15:00Z', 'action' => 'login' },
        { 'timestamp' => '2024-01-01T10:45:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-01-01T11:00:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-01-02T09:30:00Z', 'action' => 'logout' }
      ]
    end

    context 'when activities array is empty' do
      it 'returns an empty array' do
        result = reporter.format_timeline([])

        expect(result).to eq([])
      end
    end

    context 'when grouping by day' do
      it 'groups activities by date and aggregates counts' do
        result = reporter.format_timeline(activities, :day)

        expect(result.size).to eq(2)
        first_day = result.find { |r| r[:period] == '2024-01-01' }
        second_day = result.find { |r| r[:period] == '2024-01-02' }

        expect(first_day[:total_actions]).to eq(3)
        expect(first_day[:actions]).to eq('login' => 1, 'click' => 2)
        expect(first_day[:first_timestamp]).to eq('2024-01-01T10:15:00Z')
        expect(first_day[:last_timestamp]).to eq('2024-01-01T11:00:00Z')

        expect(second_day[:total_actions]).to eq(1)
        expect(second_day[:actions]).to eq('logout' => 1)
      end
    end

    context 'when grouping by hour' do
      it 'groups activities by hour' do
        result = reporter.format_timeline(activities, :hour)

        periods = result.map { |r| r[:period] }
        expect(periods).to include('2024-01-01 10:00', '2024-01-01 11:00', '2024-01-02 09:00')

        ten_am = result.find { |r| r[:period] == '2024-01-01 10:00' }
        expect(ten_am[:total_actions]).to eq(2)
        expect(ten_am[:actions]).to eq('login' => 1, 'click' => 1)
      end
    end

    context 'when grouping by week' do
      it 'groups activities by ISO week' do
        result = reporter.format_timeline(activities, :week)

        expect(result.size).to eq(1)
        expect(result.first[:period]).to match(/\A2024-W\d{2}\z/)
        expect(result.first[:total_actions]).to eq(4)
      end
    end

    context 'when grouping by month' do
      it 'groups activities by month' do
        result = reporter.format_timeline(activities, :month)

        expect(result.size).to eq(1)
        expect(result.first[:period]).to eq('2024-01')
        expect(result.first[:total_actions]).to eq(4)
      end
    end

    context 'when grouping by an unknown key' do
      it 'defaults to grouping by day' do
        result = reporter.format_timeline(activities, :unknown)

        periods = result.map { |r| r[:period] }
        expect(periods).to include('2024-01-01', '2024-01-02')
      end
    end

    context 'when timestamps are invalid' do
      let(:activities_with_invalid) do
        [
          { 'timestamp' => 'invalid-timestamp', 'action' => 'login' }
        ]
      end

      it 'falls back to current time without raising an error' do
        allow(Time).to receive(:now).and_return(Time.parse('2024-01-05T00:00:00Z'))

        result = reporter.format_timeline(activities_with_invalid, :day)

        expect(result.size).to eq(1)
        expect(result.first[:period]).to eq('2024-01-05')
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
      it 'returns JSON data in the response' do
        result = reporter.export_to_json(report)

        expect(result[:success]).to eq(true)
        expect(result[:data]).to be_a(String)
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq(1)
        expect(parsed['summary']['total_actions']).to eq(5)
      end
    end

    context 'when filepath is provided' do
      let(:filepath) { 'tmp/test_report.json' }

      before do
        allow(File).to receive(:write).and_return(100)
      end

      it 'writes JSON to the file and returns metadata' do
        result = reporter.export_to_json(report, filepath)

        expect(File).to have_received(:write).with(filepath, kind_of(String))
        expect(result[:success]).to eq(true)
        expect(result[:filepath]).to eq(filepath)
        expect(result[:size]).to be_a(Integer)
      end
    end

    context 'when an error occurs during file write' do
      let(:filepath) { 'tmp/test_report.json' }

      before do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      end

      it 'returns a failure hash with the error message' do
        result = reporter.export_to_json(report, filepath)

        expect(result[:success]).to eq(false)
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    let(:user_ids) { [1, 2, 3] }

    let(:activities_user1) do
      [
        { 'timestamp' => '2024-01-01T10:00:00Z', 'action' => 'login' }
      ]
    end
    let(:activities_user2) do
      [
        { 'timestamp' => '2024-01-01T11:00:00Z', 'action' => 'click' }
      ]
    end
    let(:activities_user3) do
      [
        { 'timestamp' => '2024-01-01T12:00:00Z', 'action' => 'logout' }
      ]
    end

    let(:stats_user1) do
      {
        total_actions: 10,
        unique_actions: 3,
        action_counts: {},
        first_activity: '2024-01-01T10:00:00Z',
        last_activity: '2024-01-02T10:00:00Z',
        most_frequent: 'login'
      }
    end
    let(:stats_user2) do
      {
        total_actions: 5,
        unique_actions: 2,
        action_counts: {},
        first_activity: '2024-01-01T11:00:00Z',
        last_activity: '2024-01-02T11:00:00Z',
        most_frequent: 'click'
      }
    end
    let(:stats_user3) do
      {
        total_actions: 20,
        unique_actions: 4,
        action_counts: {},
        first_activity: '2024-01-01T12:00:00Z',
        last_activity: '2024-01-02T12:00:00Z',
        most_frequent: 'logout'
      }
    end

    before do
      allow(reporter).to receive(:fetch_user_activities).with(1).and_return(activities_user1)
      allow(reporter).to receive(:fetch_user_activities).with(2).and_return(activities_user2)
      allow(reporter).to receive(:fetch_user_activities).with(3).and_return(activities_user3)

      allow(reporter).to receive(:fetch_activity_stats).with(1).and_return(stats_user1)
      allow(reporter).to receive(:fetch_activity_stats).with(2).and_return(stats_user2)
      allow(reporter).to receive(:fetch_activity_stats).with(3).and_return(stats_user3)

      allow(reporter).to receive(:fetch_user_score).with(activities_user1).and_return(50.0)
      allow(reporter).to receive(:fetch_user_score).with(activities_user2).and_return(75.0)
      allow(reporter).to receive(:fetch_user_score).with(activities_user3).and_return(25.0)
    end

    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        allow(Time).to receive(:now).and_return(Time.parse('2024-01-10T12:00:00Z'))

        result = reporter.compare_users([1])

        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq('2024-01-10T12:00:00Z')
      end
    end

    context 'when multiple users are provided' do
      it 'returns comparisons sorted by engagement_score descending' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].size).to eq(3)

        scores = result[:comparisons].map { |c| c[:engagement_score] }
        expect(scores).to eq(scores.sort.reverse)

        expect(result[:comparisons].map { |c| c[:user_id] }).to eq([2, 1, 3])
      end

      it 'includes top_user and average_score' do
        result = reporter.compare_users(user_ids)

        expect(result[:top_user]).to eq(2)
        expected_average = ((75.0 + 50.0 + 25.0) / 3.0).round(2)
        expect(result[:average_score]).to eq(expected_average)
      end

      it 'includes most_frequent_action and total_actions for each user' do
        result = reporter.compare_users(user_ids)

        comparison1 = result[:comparisons].find { |c| c[:user_id] == 1 }
        comparison2 = result[:comparisons].find { |c| c[:user_id] == 2 }
        comparison3 = result[:comparisons].find { |c| c[:user_id] == 3 }

        expect(comparison1[:total_actions]).to eq(10)
        expect(comparison1[:most_frequent_action]).to eq('login')

        expect(comparison2[:total_actions]).to eq(5)
        expect(comparison2[:most_frequent_action]).to eq('click')

        expect(comparison3[:total_actions]).to eq(20)
        expect(comparison3[:most_frequent_action]).to eq('logout')
      end
    end
  end

  describe '#format_pattern' do
    let(:pattern) do
      {
        'pattern_type' => 'daily',
        'description' => 'Logs in every day',
        'confidence' => 0.95
      }
    end

    it 'formats a raw pattern hash into the expected structure' do
      result = reporter.send(:format_pattern, pattern)

      expect(result).to eq(
        type: 'daily',
        description: 'Logs in every day',
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
    let(:patterns) { Array.new(pattern_count) { {} } }
    let(:anomalies) { Array.new(anomaly_count) { {} } }

    context 'when user_score is high' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 0 }

      it 'includes highly engaged insight' do
        insights = reporter.send(:generate_insights, stats, patterns, 80, anomalies)

        expect(insights).to include('Highly engaged user with strong activity patterns')
      end
    end

    context 'when user_score is moderate' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 0 }

      it 'includes moderately engaged insight' do
        insights = reporter.send(:generate_insights, stats, patterns, 60, anomalies)

        expect(insights).to include('Moderately engaged user with regular activity')
      end
    end

    context 'when user_score is low' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 0 }

      it 'includes low engagement insight' do
        insights = reporter.send(:generate_insights, stats, patterns, 40, anomalies)

        expect(insights).to include('Low engagement - consider re-engagement strategies')
      end
    end

    context 'when unique_actions is high' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 11 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 0 }

      it 'includes diverse activity profile insight' do
        insights = reporter.send(:generate_insights, stats, patterns, 40, anomalies)

        expect(insights).to include('Diverse activity profile across multiple action types')
      end
    end

    context 'when many patterns exist' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 3 }
      let(:anomaly_count) { 0 }

      it 'includes behavioral patterns detected insight' do
        insights = reporter.send(:generate_insights, stats, patterns, 40, anomalies)

        expect(insights).to include('Clear behavioral patterns detected')
      end
    end

    context 'when anomalies exist' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 2 }

      it 'includes anomalies detected insight with count' do
        insights = reporter.send(:generate_insights, stats, patterns, 40, anomalies)

        expect(insights.any? { |i| i.include?('2 anomalous activities detected') }).to eq(true)
      end
    end

    context 'when total_actions is very high' do
      let(:total_actions) { 150 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 0 }

      it 'includes power user insight' do
        insights = reporter.send(:generate_insights, stats, patterns, 40, anomalies)

        expect(insights).to include('Power user - high volume of activities')
      end
    end
  end

  describe '#parse_timestamp' do
    context 'with a valid timestamp string' do
      it 'parses and returns a Time object' do
        time = reporter.send(:parse_timestamp, '2024-01-01T10:00:00Z')

        expect(time).to be_a(Time)
        expect(time.utc.iso8601).to eq('2024-01-01T10:00:00Z')
      end
    end

    context 'with an invalid timestamp string' do
      it 'returns current time when parsing fails' do
        fixed_time = Time.parse('2024-01-05T00:00:00Z')
        allow(Time).to receive(:now).and_return(fixed_time)

        time = reporter.send(:parse_timestamp, 'invalid')

        expect(time).to eq(fixed_time)
      end
    end
  end

  describe '#error_report' do
    it 'returns a standardized error hash with message and timestamp' do
      allow(Time).to receive(:now).and_return(Time.parse('2024-01-10T12:00:00Z'))

      result = reporter.send(:error_report, 'Something went wrong')

      expect(result[:error]).to eq(true)
      expect(result[:message]).to eq('Something went wrong')
      expect(result[:generated_at]).to eq('2024-01-10T12:00:00Z')
    end
  end
end
