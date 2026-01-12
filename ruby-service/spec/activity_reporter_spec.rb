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
        { 'pattern_type' => 'daily', 'description' => 'Logs in daily', 'confidence' => 0.9 },
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
      it 'returns a structured report hash with expected keys' do
        result = reporter.generate_report(user_id)

        expect(result).to be_a(Hash)
        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq('2024-01-10T12:00:00Z')
        expect(result[:summary]).to include(
          total_actions: 3,
          unique_actions: 3,
          engagement_score: user_score,
          first_activity: '2024-01-01T10:00:00Z',
          last_activity: '2024-01-02T09:30:00Z'
        )
        expect(result[:action_breakdown]).to eq(stats[:action_counts])
        expect(result[:patterns]).to all(include(:type, :description, :confidence))
        expect(result[:anomalies]).to eq(anomalies)
        expect(result[:timeline]).to be_an(Array)
        expect(result[:insights]).to be_an(Array)
      end

      it 'formats patterns using format_pattern' do
        expect(reporter).to receive(:format_pattern).twice.and_call_original

        result = reporter.generate_report(user_id)

        expect(result[:patterns]).to eq(
          [
            {
              type: 'daily',
              description: 'Logs in daily',
              confidence: 0.9
            },
            {
              type: 'morning',
              description: 'Active in the morning',
              confidence: 0.8
            }
          ]
        )
      end

      it 'uses the provided group_by option for timeline' do
        expect(reporter).to receive(:format_timeline).with(activities, :hour).and_call_original

        reporter.generate_report(user_id, group_by: :hour)
      end

      it 'defaults group_by to :day when not provided' do
        expect(reporter).to receive(:format_timeline).with(activities, :day).and_call_original

        reporter.generate_report(user_id)
      end

      it 'calls generate_insights with correct arguments' do
        expect(reporter).to receive(:generate_insights).with(stats, patterns, user_score, anomalies).and_call_original

        reporter.generate_report(user_id)
      end
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report' do
        result = reporter.generate_report(user_id)

        expect(result).to include(:error, :message, :generated_at)
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
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
        { 'timestamp' => '2024-01-01T10:15:00Z', 'action' => 'login' },
        { 'timestamp' => '2024-01-01T10:45:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-01-01T11:05:00Z', 'action' => 'click' },
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
      it 'groups activities by day and aggregates counts' do
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

        expect(result.map { |r| r[:period] }).to contain_exactly(
          '2024-01-01 10:00',
          '2024-01-01 11:00',
          '2024-01-02 09:00'
        )

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

    context 'when grouping by an unknown period' do
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

      it 'uses parse_timestamp which falls back to Time.now' do
        fake_now = Time.parse('2024-02-01T00:00:00Z')
        allow(Time).to receive(:now).and_return(fake_now)

        result = reporter.format_timeline(activities_with_invalid, :day)

        expect(result.size).to eq(1)
        expect(result.first[:period]).to eq(fake_now.strftime('%Y-%m-%d'))
      end
    end
  end

  describe '#export_to_json' do
    let(:report_hash) do
      {
        user_id: 1,
        summary: { total_actions: 5 }
      }
    end

    before do
      allow(JSON).to receive(:pretty_generate).and_call_original
    end

    context 'when filepath is not provided' do
      it 'returns success with JSON data' do
        result = reporter.export_to_json(report_hash)

        expect(result[:success]).to be true
        expect(result[:data]).to be_a(String)
        expect(JSON.parse(result[:data])).to eq(JSON.parse(JSON.pretty_generate(report_hash)))
      end
    end

    context 'when filepath is provided' do
      let(:filepath) { 'tmp/test_report.json' }

      before do
        allow(File).to receive(:write).and_return(100)
      end

      it 'writes JSON to the file and returns metadata' do
        result = reporter.export_to_json(report_hash, filepath)

        expect(File).to have_received(:write).with(filepath, JSON.pretty_generate(report_hash))
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(filepath)
        expect(result[:size]).to eq(JSON.pretty_generate(report_hash).bytesize)
      end
    end

    context 'when an error occurs during export' do
      before do
        allow(JSON).to receive(:pretty_generate).and_raise(StandardError.new('boom'))
      end

      it 'returns a failure hash with error message' do
        result = reporter.export_to_json(report_hash)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('boom')
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
      let(:activities_user1) do
        [
          { 'timestamp' => '2024-01-01T10:00:00Z', 'action' => 'login' }
        ]
      end
      let(:activities_user2) do
        [
          { 'timestamp' => '2024-01-01T11:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2024-01-01T12:00:00Z', 'action' => 'click' }
        ]
      end
      let(:activities_user3) do
        [
          { 'timestamp' => '2024-01-02T09:00:00Z', 'action' => 'logout' }
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
          unique_actions: 1,
          action_counts: { 'click' => 2 },
          first_activity: '2024-01-01T11:00:00Z',
          last_activity: '2024-01-01T12:00:00Z',
          most_frequent: 'click'
        }
      end
      let(:stats_user3) do
        {
          total_actions: 1,
          unique_actions: 1,
          action_counts: { 'logout' => 1 },
          first_activity: '2024-01-02T09:00:00Z',
          last_activity: '2024-01-02T09:00:00Z',
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

        allow(reporter).to receive(:fetch_user_score).with(activities_user1).and_return(10.0)
        allow(reporter).to receive(:fetch_user_score).with(activities_user2).and_return(90.0)
        allow(reporter).to receive(:fetch_user_score).with(activities_user3).and_return(50.0)
      end

      it 'returns comparison data for all users' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].size).to eq(3)
        expect(result[:comparisons]).to all(include(:user_id, :total_actions, :engagement_score, :most_frequent_action))
      end

      it 'sorts users by engagement_score descending and sets top_user' do
        result = reporter.compare_users(user_ids)

        scores = result[:comparisons].map { |c| c[:engagement_score] }
        expect(scores).to eq(scores.sort.reverse)
        expect(result[:top_user]).to eq(2)
      end

      it 'calculates the average_score correctly' do
        result = reporter.compare_users(user_ids)

        expected_average = ((10.0 + 90.0 + 50.0) / 3.0).round(2)
        expect(result[:average_score]).to eq(expected_average)
      end
    end
  end

  describe '#format_pattern' do
    let(:pattern) do
      {
        'pattern_type' => 'daily',
        'description' => 'Logs in daily',
        'confidence' => 0.95
      }
    end

    it 'formats a raw pattern hash into a symbolized structure' do
      result = reporter.send(:format_pattern, pattern)

      expect(result).to eq(
        type: 'daily',
        description: 'Logs in daily',
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
      let(:total_actions) { 150 }
      let(:unique_actions) { 12 }
      let(:pattern_count) { 3 }
      let(:anomaly_count) { 2 }
      let(:user_score) { 80.0 }

      it 'includes appropriate high engagement insights' do
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
        expect(insights).not_to include('Highly engaged user with strong activity patterns')
        expect(insights).not_to include('Low engagement - consider re-engagement strategies')
      end
    end

    context 'when user_score is low' do
      let(:total_actions) { 10 }
      let(:unique_actions) { 2 }
      let(:pattern_count) { 0 }
      let(:anomaly_count) { 0 }
      let(:user_score) { 30.0 }

      it 'includes low engagement insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Low engagement - consider re-engagement strategies')
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
      it 'returns Time.now as a fallback' do
        fake_now = Time.parse('2024-03-01T00:00:00Z')
        allow(Time).to receive(:now).and_return(fake_now)

        time = reporter.send(:parse_timestamp, 'not-a-timestamp')

        expect(time).to eq(fake_now)
      end
    end
  end

  describe '#error_report' do
    it 'returns a standardized error hash' do
      allow(Time).to receive(:now).and_return(Time.parse('2024-01-10T12:00:00Z'))

      result = reporter.send(:error_report, 'Something went wrong')

      expect(result[:error]).to be true
      expect(result[:message]).to eq('Something went wrong')
      expect(result[:generated_at]).to eq('2024-01-10T12:00:00Z')
    end
  end
end
