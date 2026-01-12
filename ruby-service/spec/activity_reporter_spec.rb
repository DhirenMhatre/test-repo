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
    it 'sets the go_service_url and python_service_url with custom values' do
      instance = described_class.new(
        go_service_url: 'http://custom-go',
        python_service_url: 'http://custom-python'
      )

      expect(instance.instance_variable_get(:@go_service_url)).to eq('http://custom-go')
      expect(instance.instance_variable_get(:@python_service_url)).to eq('http://custom-python')
    end

    it 'uses default service URLs when none are provided' do
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
        { 'pattern_type' => 'daily_login', 'description' => 'Logs in daily', 'confidence' => 0.9 },
        { 'pattern_type' => 'evening_usage', 'description' => 'Uses app in evening', 'confidence' => 0.7 }
      ]
    end
    let(:user_score) { 80.5 }
    let(:anomalies) do
      [
        { 'timestamp' => '2024-01-03T03:00:00Z', 'action' => 'login', 'reason' => 'unusual_time' }
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

    context 'when user has activities' do
      it 'returns a structured report hash with expected keys' do
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
            { type: 'daily_login', description: 'Logs in daily', confidence: 0.9 },
            { type: 'evening_usage', description: 'Uses app in evening', confidence: 0.7 }
          ]
        )
        expect(result[:anomalies]).to eq(anomalies)
        expect(result[:timeline]).to be_an(Array)
        expect(result[:insights]).to be_an(Array)
      end

      it 'passes group_by option to format_timeline' do
        expect(reporter).to receive(:format_timeline).with(activities, :week).and_call_original

        reporter.generate_report(user_id, group_by: :week)
      end

      it 'defaults group_by to :day when not provided' do
        expect(reporter).to receive(:format_timeline).with(activities, :day).and_call_original

        reporter.generate_report(user_id)
      end
    end

    context 'when user has no activities' do
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
        { 'timestamp' => '2024-01-01T11:05:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-01-02T09:30:00Z', 'action' => 'logout' }
      ]
    end

    before do
      allow(Time).to receive(:now).and_return(Time.parse('2024-01-01T00:00:00Z'))
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

        day1 = result.find { |r| r[:period] == '2024-01-01' }
        day2 = result.find { |r| r[:period] == '2024-01-02' }

        expect(day1[:total_actions]).to eq(3)
        expect(day1[:actions]).to eq('login' => 1, 'click' => 2)
        expect(day1[:first_timestamp]).to eq('2024-01-01T10:15:00Z')
        expect(day1[:last_timestamp]).to eq('2024-01-01T11:05:00Z')

        expect(day2[:total_actions]).to eq(1)
        expect(day2[:actions]).to eq('logout' => 1)
        expect(day2[:first_timestamp]).to eq('2024-01-02T09:30:00Z')
        expect(day2[:last_timestamp]).to eq('2024-01-02T09:30:00Z')
      end
    end

    context 'when grouping by hour' do
      it 'groups activities by hour' do
        result = reporter.format_timeline(activities, :hour)

        expect(result.size).to eq(3)

        hour1 = result.find { |r| r[:period] == '2024-01-01 10:00' }
        hour2 = result.find { |r| r[:period] == '2024-01-01 11:00' }
        hour3 = result.find { |r| r[:period] == '2024-01-02 09:00' }

        expect(hour1[:total_actions]).to eq(2)
        expect(hour1[:actions]).to eq('login' => 1, 'click' => 1)

        expect(hour2[:total_actions]).to eq(1)
        expect(hour2[:actions]).to eq('click' => 1)

        expect(hour3[:total_actions]).to eq(1)
        expect(hour3[:actions]).to eq('logout' => 1)
      end
    end

    context 'when grouping by week' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-01T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-01-08T10:15:00Z', 'action' => 'login' }
        ]
      end

      it 'groups activities by ISO week' do
        result = reporter.format_timeline(activities, :week)

        expect(result.map { |r| r[:period] }).to match_array(%w[2024-W01 2024-W02])
      end
    end

    context 'when grouping by month' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-01T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-02-01T10:15:00Z', 'action' => 'login' }
        ]
      end

      it 'groups activities by month' do
        result = reporter.format_timeline(activities, :month)

        expect(result.map { |r| r[:period] }).to match_array(%w[2024-01 2024-02])
      end
    end

    context 'when grouping by unknown period' do
      it 'defaults to grouping by day' do
        result = reporter.format_timeline(activities, :unknown)

        expect(result.map { |r| r[:period] }).to match_array(%w[2024-01-01 2024-01-02])
      end
    end

    context 'ordering' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-02T10:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-01-01T10:00:00Z', 'action' => 'login' }
        ]
      end

      it 'sorts the result by period ascending' do
        result = reporter.format_timeline(activities, :day)

        expect(result.map { |r| r[:period] }).to eq(%w[2024-01-01 2024-01-02])
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
      let(:filepath) { File.join(Dir.tmpdir, "activity_report_#{Time.now.to_i}.json") }

      after do
        File.delete(filepath) if File.exist?(filepath)
      end

      it 'writes JSON to the file and returns metadata' do
        result = reporter.export_to_json(report, filepath)

        expect(result[:success]).to eq(true)
        expect(result[:filepath]).to eq(filepath)
        expect(result[:size]).to be > 0
        expect(File).to exist(filepath)

        file_content = File.read(filepath)
        parsed = JSON.parse(file_content)
        expect(parsed['user_id']).to eq(1)
      end
    end

    context 'when an error occurs during file write' do
      let(:filepath) { '/invalid/path/report.json' }

      before do
        allow(File).to receive(:write).and_raise(StandardError.new('disk error'))
      end

      it 'returns a failure hash with error message' do
        result = reporter.export_to_json(report, filepath)

        expect(result[:success]).to eq(false)
        expect(result[:error]).to eq('disk error')
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
        { 'timestamp' => '2024-01-01T11:00:00Z', 'action' => 'login' },
        { 'timestamp' => '2024-01-01T12:00:00Z', 'action' => 'click' }
      ]
    end
    let(:activities_user3) do
      [
        { 'timestamp' => '2024-01-01T13:00:00Z', 'action' => 'login' },
        { 'timestamp' => '2024-01-01T14:00:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-01-01T15:00:00Z', 'action' => 'logout' }
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
        first_activity: '2024-01-01T13:00:00Z',
        last_activity: '2024-01-01T15:00:00Z',
        most_frequent: 'login'
      }
    end

    before do
      allow(reporter).to receive(:fetch_user_activities).with(1).and_return(activities_user1)
      allow(reporter).to receive(:fetch_user_activities).with(2).and_return(activities_user2)
      allow(reporter).to receive(:fetch_user_activities).with(3).and_return(activities_user3)

      allow(reporter).to receive(:fetch_activity_stats).with(1).and_return(stats_user1)
      allow(reporter).to receive(:fetch_activity_stats).with(2).and_return(stats_user2)
      allow(reporter).to receive(:fetch_activity_stats).with(3).and_return(stats_user3)

      allow(reporter).to receive(:fetch_user_score).with(activities_user1).and_return(10.0)
      allow(reporter).to receive(:fetch_user_score).with(activities_user2).and_return(50.0)
      allow(reporter).to receive(:fetch_user_score).with(activities_user3).and_return(90.0)
    end

    context 'when fewer than 2 users are provided' do
      it 'returns an error report' do
        allow(Time).to receive(:now).and_return(Time.parse('2024-01-10T12:00:00Z'))

        result = reporter.compare_users([1])

        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq('2024-01-10T12:00:00Z')
      end
    end

    context 'when multiple users are provided' do
      it 'returns comparison data sorted by engagement_score descending' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].size).to eq(3)

        scores = result[:comparisons].map { |c| c[:engagement_score] }
        expect(scores).to eq(scores.sort.reverse)

        top = result[:comparisons].first
        expect(result[:top_user]).to eq(top[:user_id])
      end

      it 'includes total_actions and most_frequent_action for each user' do
        result = reporter.compare_users(user_ids)

        comparison1 = result[:comparisons].find { |c| c[:user_id] == 1 }
        comparison2 = result[:comparisons].find { |c| c[:user_id] == 2 }
        comparison3 = result[:comparisons].find { |c| c[:user_id] == 3 }

        expect(comparison1[:total_actions]).to eq(1)
        expect(comparison1[:most_frequent_action]).to eq('login')

        expect(comparison2[:total_actions]).to eq(2)
        expect(comparison2[:most_frequent_action]).to eq('login')

        expect(comparison3[:total_actions]).to eq(3)
        expect(comparison3[:most_frequent_action]).to eq('login')
      end

      it 'calculates the average engagement score' do
        result = reporter.compare_users(user_ids)

        expected_average = ((10.0 + 50.0 + 90.0) / 3.0).round(2)
        expect(result[:average_score]).to eq(expected_average)
      end
    end
  end

  describe '#format_pattern' do
    let(:pattern) do
      {
        'pattern_type' => 'daily_login',
        'description' => 'Logs in every day',
        'confidence' => 0.95
      }
    end

    it 'formats a raw pattern hash into the expected structure' do
      result = reporter.send(:format_pattern, pattern)

      expect(result).to eq(
        type: 'daily_login',
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

    let(:total_actions) { 10 }
    let(:unique_actions) { 3 }
    let(:pattern_count) { 0 }
    let(:anomaly_count) { 0 }

    context 'when user_score is high' do
      let(:user_score) { 80 }

      it 'includes high engagement insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Highly engaged user with strong activity patterns')
      end
    end

    context 'when user_score is moderate' do
      let(:user_score) { 60 }

      it 'includes moderate engagement insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Moderately engaged user with regular activity')
      end
    end

    context 'when user_score is low' do
      let(:user_score) { 40 }

      it 'includes low engagement insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Low engagement - consider re-engagement strategies')
      end
    end

    context 'when unique_actions is high' do
      let(:user_score) { 40 }
      let(:unique_actions) { 11 }

      it 'includes diverse activity profile insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Diverse activity profile across multiple action types')
      end
    end

    context 'when many patterns are detected' do
      let(:user_score) { 40 }
      let(:pattern_count) { 3 }

      it 'includes behavioral patterns insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Clear behavioral patterns detected')
      end
    end

    context 'when anomalies are present' do
      let(:user_score) { 40 }
      let(:anomaly_count) { 2 }

      it 'includes anomalies insight with count' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('2 anomalous activities detected - review recommended')
      end
    end

    context 'when total_actions is high' do
      let(:user_score) { 40 }
      let(:total_actions) { 150 }

      it 'includes power user insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

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
        fixed_time = Time.parse('2024-01-01T00:00:00Z')
        allow(Time).to receive(:now).and_return(fixed_time)

        time = reporter.send(:parse_timestamp, 'invalid-timestamp')

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
