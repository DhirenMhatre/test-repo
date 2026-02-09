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
    it 'sets the go_service_url and python_service_url' do
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
        { 'pattern_type' => 'evening_usage', 'description' => 'Uses app in evening', 'confidence' => 0.8 }
      ]
    end
    let(:user_score) { 80.5 }
    let(:anomalies) do
      [
        { 'timestamp' => '2024-01-03T01:00:00Z', 'action' => 'login', 'reason' => 'unusual_time' }
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

    context 'when user has no activities' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report' do
        result = reporter.generate_report(user_id)

        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(Time.now.iso8601)
      end
    end

    context 'when user has activities' do
      it 'returns a report hash with expected top-level keys' do
        result = reporter.generate_report(user_id)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(Time.now.iso8601)
        expect(result).to have_key(:summary)
        expect(result).to have_key(:action_breakdown)
        expect(result).to have_key(:patterns)
        expect(result).to have_key(:anomalies)
        expect(result).to have_key(:timeline)
        expect(result).to have_key(:insights)
      end

      it 'includes correct summary data' do
        result = reporter.generate_report(user_id)
        summary = result[:summary]

        expect(summary[:total_actions]).to eq(3)
        expect(summary[:unique_actions]).to eq(3)
        expect(summary[:engagement_score]).to eq(user_score)
        expect(summary[:first_activity]).to eq('2024-01-01T10:00:00Z')
        expect(summary[:last_activity]).to eq('2024-01-02T09:30:00Z')
      end

      it 'includes action breakdown from stats' do
        result = reporter.generate_report(user_id)

        expect(result[:action_breakdown]).to eq(stats[:action_counts])
      end

      it 'formats patterns using format_pattern' do
        result = reporter.generate_report(user_id)

        expect(result[:patterns]).to eq(
          [
            { type: 'daily_login', description: 'Logs in daily', confidence: 0.9 },
            { type: 'evening_usage', description: 'Uses app in evening', confidence: 0.8 }
          ]
        )
      end

      it 'includes anomalies as returned by fetch_anomalies' do
        result = reporter.generate_report(user_id)

        expect(result[:anomalies]).to eq(anomalies)
      end

      it 'uses default group_by :day for timeline' do
        expect(reporter).to receive(:format_timeline).with(activities, :day).and_call_original

        reporter.generate_report(user_id)
      end

      it 'passes custom group_by option to format_timeline' do
        expect(reporter).to receive(:format_timeline).with(activities, :hour).and_call_original

        reporter.generate_report(user_id, group_by: :hour)
      end

      it 'generates insights based on stats, patterns, score, and anomalies' do
        result = reporter.generate_report(user_id)

        expect(result[:insights]).to be_an(Array)
        expect(result[:insights]).not_to be_empty
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

        day1 = result.find { |r| r[:period] == '2024-01-01' }
        day2 = result.find { |r| r[:period] == '2024-01-02' }

        expect(day1[:total_actions]).to eq(3)
        expect(day1[:actions]).to eq('login' => 1, 'click' => 2)
        expect(day1[:first_timestamp]).to eq('2024-01-01T10:15:00Z')
        expect(day1[:last_timestamp]).to eq('2024-01-01T11:00:00Z')

        expect(day2[:total_actions]).to eq(1)
        expect(day2[:actions]).to eq('logout' => 1)
        expect(day2[:first_timestamp]).to eq('2024-01-02T09:30:00Z')
        expect(day2[:last_timestamp]).to eq('2024-01-02T09:30:00Z')
      end
    end

    context 'when grouping by hour' do
      it 'groups activities by hour' do
        result = reporter.format_timeline(activities, :hour)

        periods = result.map { |r| r[:period] }

        expect(periods).to include('2024-01-01 10:00')
        expect(periods).to include('2024-01-01 11:00')
        expect(periods).to include('2024-01-02 09:00')

        hour_10 = result.find { |r| r[:period] == '2024-01-01 10:00' }
        expect(hour_10[:total_actions]).to eq(2)
        expect(hour_10[:actions]).to eq('login' => 1, 'click' => 1)
      end
    end

    context 'when grouping by week' do
      it 'groups activities by ISO week' do
        result = reporter.format_timeline(activities, :week)

        expect(result.size).to eq(1)
        expect(result.first[:period]).to match(/\A2024-W\d{2}\z/)
      end
    end

    context 'when grouping by month' do
      it 'groups activities by month' do
        result = reporter.format_timeline(activities, :month)

        expect(result.size).to eq(1)
        expect(result.first[:period]).to eq('2024-01')
      end
    end

    context 'when grouping by unknown key' do
      it 'defaults to grouping by day' do
        result = reporter.format_timeline(activities, :unknown)

        expect(result.map { |r| r[:period] }).to contain_exactly('2024-01-01', '2024-01-02')
      end
    end

    context 'when timestamps are invalid' do
      let(:activities_with_invalid) do
        [
          { 'timestamp' => 'invalid-timestamp', 'action' => 'login' }
        ]
      end

      it 'falls back to current time via parse_timestamp and still returns a timeline' do
        allow(Time).to receive(:now).and_return(Time.parse('2024-01-05T00:00:00Z'))

        result = reporter.format_timeline(activities_with_invalid, :day)

        expect(result.size).to eq(1)
        expect(result.first[:total_actions]).to eq(1)
        expect(result.first[:actions]).to eq('login' => 1)
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
      it 'returns success with JSON data' do
        result = reporter.export_to_json(report)

        expect(result[:success]).to be true
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

      it 'writes JSON to the given file and returns metadata' do
        result = reporter.export_to_json(report, filepath)

        expect(File).to have_received(:write).with(filepath, kind_of(String))
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(filepath)
        expect(result[:size]).to be_a(Integer)
      end
    end

    context 'when an error occurs during file write' do
      let(:filepath) { 'tmp/test_report.json' }

      before do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      end

      it 'returns a failure hash with error message' do
        result = reporter.export_to_json(report, filepath)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than 2 user_ids are provided' do
      it 'returns an error report' do
        result = reporter.compare_users([1])

        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
      end
    end

    context 'when multiple users are provided' do
      let(:user_ids) { [1, 2, 3] }
      let(:activities_user1) { [{ 'timestamp' => '2024-01-01T10:00:00Z', 'action' => 'login' }] }
      let(:activities_user2) { [{ 'timestamp' => '2024-01-01T11:00:00Z', 'action' => 'click' }] }
      let(:activities_user3) { [{ 'timestamp' => '2024-01-01T12:00:00Z', 'action' => 'logout' }] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(1).and_return(activities_user1)
        allow(reporter).to receive(:fetch_user_activities).with(2).and_return(activities_user2)
        allow(reporter).to receive(:fetch_user_activities).with(3).and_return(activities_user3)

        allow(reporter).to receive(:fetch_activity_stats).with(1).and_return(
          total_actions: 10,
          unique_actions: 2,
          action_counts: { 'login' => 10 },
          first_activity: '2024-01-01T10:00:00Z',
          last_activity: '2024-01-01T10:30:00Z',
          most_frequent: 'login'
        )
        allow(reporter).to receive(:fetch_activity_stats).with(2).and_return(
          total_actions: 5,
          unique_actions: 1,
          action_counts: { 'click' => 5 },
          first_activity: '2024-01-01T11:00:00Z',
          last_activity: '2024-01-01T11:30:00Z',
          most_frequent: 'click'
        )
        allow(reporter).to receive(:fetch_activity_stats).with(3).and_return(
          total_actions: 20,
          unique_actions: 3,
          action_counts: { 'logout' => 20 },
          first_activity: '2024-01-01T12:00:00Z',
          last_activity: '2024-01-01T12:30:00Z',
          most_frequent: 'logout'
        )

        allow(reporter).to receive(:fetch_user_score).with(activities_user1).and_return(50.0)
        allow(reporter).to receive(:fetch_user_score).with(activities_user2).and_return(75.0)
        allow(reporter).to receive(:fetch_user_score).with(activities_user3).and_return(25.0)
      end

      it 'returns comparison data for each user' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].size).to eq(3)

        user_ids.each do |id|
          expect(result[:comparisons].map { |c| c[:user_id] }).to include(id)
        end
      end

      it 'sorts comparisons by engagement_score descending' do
        result = reporter.compare_users(user_ids)
        scores = result[:comparisons].map { |c| c[:engagement_score] }

        expect(scores).to eq(scores.sort.reverse)
      end

      it 'sets top_user to the user with highest engagement_score' do
        result = reporter.compare_users(user_ids)

        expect(result[:top_user]).to eq(2)
      end

      it 'calculates the average_score correctly' do
        result = reporter.compare_users(user_ids)

        expected_average = ((50.0 + 75.0 + 25.0) / 3.0).round(2)
        expect(result[:average_score]).to eq(expected_average)
      end

      it 'includes most_frequent_action from stats' do
        result = reporter.compare_users(user_ids)
        comparison_for_1 = result[:comparisons].find { |c| c[:user_id] == 1 }

        expect(comparison_for_1[:most_frequent_action]).to eq('login')
      end
    end
  end

  describe '#format_pattern' do
    it 'formats a pattern hash into the expected structure' do
      pattern = {
        'pattern_type' => 'daily_login',
        'description' => 'Logs in every day',
        'confidence' => 0.95
      }

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

    context 'when user_score is high' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 0 }

      it 'includes high engagement insight' do
        insights = reporter.send(:generate_insights, stats, patterns, 80, anomalies)

        expect(insights).to include('Highly engaged user with strong activity patterns')
      end
    end

    context 'when user_score is moderate' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 0 }

      it 'includes moderate engagement insight' do
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

    context 'when many patterns are detected' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 3 }
      let(:anomaly_count) { 0 }

      it 'includes behavioral patterns insight' do
        insights = reporter.send(:generate_insights, stats, patterns, 40, anomalies)

        expect(insights).to include('Clear behavioral patterns detected')
      end
    end

    context 'when anomalies are present' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 2 }

      it 'includes anomalies insight with count' do
        insights = reporter.send(:generate_insights, stats, patterns, 40, anomalies)

        expect(insights.any? { |i| i.include?('2 anomalous activities detected') }).to be true
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
        expect(time.utc.year).to eq(2024)
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
    it 'returns an error hash with message and generated_at' do
      allow(Time).to receive(:now).and_return(Time.parse('2024-01-10T12:00:00Z'))

      result = reporter.send(:error_report, 'Something went wrong')

      expect(result[:error]).to be true
      expect(result[:message]).to eq('Something went wrong')
      expect(result[:generated_at]).to eq('2024-01-10T12:00:00Z')
    end
  end
end
