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
    let(:user_id) { 123 }
    let(:activities) do
      [
        { 'timestamp' => '2024-01-01T10:00:00Z', 'action' => 'login' },
        { 'timestamp' => '2024-01-01T11:00:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-01-02T09:30:00Z', 'action' => 'purchase' }
      ]
    end
    let(:stats) do
      {
        total_actions: 3,
        unique_actions: 3,
        action_counts: { 'login' => 1, 'click' => 1, 'purchase' => 1 },
        first_activity: '2024-01-01T10:00:00Z',
        last_activity: '2024-01-02T09:30:00Z',
        most_frequent: 'login'
      }
    end
    let(:patterns) do
      [
        { 'pattern_type' => 'daily', 'description' => 'Daily login', 'confidence' => 0.9 },
        { 'pattern_type' => 'purchase', 'description' => 'Frequent purchases', 'confidence' => 0.8 }
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
    end

    context 'when user has no activities' do
      let(:activities) { [] }

      it 'returns an error report' do
        result = reporter.generate_report(user_id)

        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'when user has activities' do
      it 'returns a report hash with expected top-level keys' do
        result = reporter.generate_report(user_id)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to be_a(String)
        expect(result[:summary]).to be_a(Hash)
        expect(result[:action_breakdown]).to eq(stats[:action_counts])
        expect(result[:patterns]).to be_an(Array)
        expect(result[:anomalies]).to eq(anomalies)
        expect(result[:timeline]).to be_an(Array)
        expect(result[:insights]).to be_an(Array)
      end

      it 'includes correct summary data' do
        result = reporter.generate_report(user_id)
        summary = result[:summary]

        expect(summary[:total_actions]).to eq(3)
        expect(summary[:unique_actions]).to eq(3)
        expect(summary[:engagement_score]).to eq(user_score)
        expect(summary[:first_activity]).to eq(stats[:first_activity])
        expect(summary[:last_activity]).to eq(stats[:last_activity])
      end

      it 'formats patterns using #format_pattern' do
        result = reporter.generate_report(user_id)

        expect(result[:patterns]).to eq(
          patterns.map do |p|
            {
              type: p['pattern_type'],
              description: p['description'],
              confidence: p['confidence']
            }
          end
        )
      end

      it 'uses :day as default group_by for timeline' do
        result = reporter.generate_report(user_id)

        periods = result[:timeline].map { |entry| entry[:period] }
        expect(periods).to contain_exactly('2024-01-01', '2024-01-02')
      end

      it 'respects custom group_by option for timeline' do
        result = reporter.generate_report(user_id, group_by: :hour)

        periods = result[:timeline].map { |entry| entry[:period] }
        expect(periods).to include('2024-01-01 10:00', '2024-01-01 11:00', '2024-01-02 09:00')
      end

      it 'generates insights using #generate_insights' do
        expect(reporter).to receive(:generate_insights).with(stats, patterns, user_score, anomalies).and_call_original

        result = reporter.generate_report(user_id)

        expect(result[:insights]).not_to be_empty
      end
    end
  end

  describe '#format_timeline' do
    let(:activities) do
      [
        { 'timestamp' => '2024-01-01T10:15:00Z', 'action' => 'login' },
        { 'timestamp' => '2024-01-01T11:45:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-01-02T09:30:00Z', 'action' => 'purchase' },
        { 'timestamp' => '2024-01-08T09:30:00Z', 'action' => 'login' }
      ]
    end

    context 'when activities array is empty' do
      it 'returns an empty array' do
        result = reporter.format_timeline([], :day)

        expect(result).to eq([])
      end
    end

    context 'when grouping by day' do
      it 'groups activities by date' do
        result = reporter.format_timeline(activities, :day)

        periods = result.map { |entry| entry[:period] }
        expect(periods).to eq(['2024-01-01', '2024-01-02', '2024-01-08'])

        first_day = result.find { |e| e[:period] == '2024-01-01' }
        expect(first_day[:total_actions]).to eq(2)
        expect(first_day[:actions]).to eq('login' => 1, 'click' => 1)
      end
    end

    context 'when grouping by hour' do
      it 'groups activities by hour' do
        result = reporter.format_timeline(activities, :hour)

        periods = result.map { |entry| entry[:period] }
        expect(periods).to include('2024-01-01 10:00', '2024-01-01 11:00', '2024-01-02 09:00', '2024-01-08 09:00')
      end
    end

    context 'when grouping by week' do
      it 'groups activities by ISO week' do
        result = reporter.format_timeline(activities, :week)

        periods = result.map { |entry| entry[:period] }
        expect(periods).to all(match(/\A\d{4}-W\d{2}\z/))
      end
    end

    context 'when grouping by month' do
      it 'groups activities by month' do
        result = reporter.format_timeline(activities, :month)

        periods = result.map { |entry| entry[:period] }.uniq
        expect(periods).to eq(['2024-01'])
      end
    end

    context 'when grouping by unknown value' do
      it 'defaults to grouping by day' do
        result = reporter.format_timeline(activities, :unknown)

        periods = result.map { |entry| entry[:period] }
        expect(periods).to eq(['2024-01-01', '2024-01-02', '2024-01-08'])
      end
    end

    it 'sorts the result by period' do
      shuffled = activities.shuffle
      result = reporter.format_timeline(shuffled, :day)

      periods = result.map { |entry| entry[:period] }
      expect(periods).to eq(periods.sort)
    end

    it 'uses first and last timestamps from the group' do
      result = reporter.format_timeline(activities, :day)
      first_day = result.find { |e| e[:period] == '2024-01-01' }

      expect(first_day[:first_timestamp]).to eq('2024-01-01T10:15:00Z')
      expect(first_day[:last_timestamp]).to eq('2024-01-01T11:45:00Z')
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

      it 'writes JSON to the file and returns metadata' do
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
        { 'timestamp' => '2024-01-02T09:00:00Z', 'action' => 'purchase' }
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
        action_counts: { 'purchase' => 1 },
        first_activity: '2024-01-02T09:00:00Z',
        last_activity: '2024-01-02T09:00:00Z',
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

      allow(reporter).to receive(:fetch_user_score).with(activities_user1).and_return(10.0)
      allow(reporter).to receive(:fetch_user_score).with(activities_user2).and_return(90.0)
      allow(reporter).to receive(:fetch_user_score).with(activities_user3).and_return(50.0)
    end

    context 'when fewer than 2 users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users([1])

        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
      end
    end

    context 'when multiple users are provided' do
      it 'returns comparison data for each user' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].size).to eq(3)

        user_ids.each do |id|
          expect(result[:comparisons].map { |c| c[:user_id] }).to include(id)
        end
      end

      it 'includes total_actions, engagement_score, and most_frequent_action for each user' do
        result = reporter.compare_users(user_ids)
        comparison = result[:comparisons].find { |c| c[:user_id] == 2 }

        expect(comparison[:total_actions]).to eq(2)
        expect(comparison[:engagement_score]).to eq(90.0)
        expect(comparison[:most_frequent_action]).to eq('click')
      end

      it 'sorts users by engagement_score descending' do
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
        expected_average = ((10.0 + 90.0 + 50.0) / 3.0).round(2)

        expect(result[:average_score]).to eq(expected_average)
      end
    end
  end

  describe '#format_pattern' do
    let(:pattern) do
      {
        'pattern_type' => 'daily',
        'description' => 'Daily login pattern',
        'confidence' => 0.95
      }
    end

    it 'returns a formatted pattern hash' do
      result = reporter.send(:format_pattern, pattern)

      expect(result).to eq(
        type: 'daily',
        description: 'Daily login pattern',
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
      let(:user_score) { 80 }

      it 'includes high engagement insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Highly engaged user with strong activity patterns')
      end
    end

    context 'when user_score is moderate' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 0 }
      let(:user_score) { 60 }

      it 'includes moderate engagement insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Moderately engaged user with regular activity')
      end
    end

    context 'when user_score is low' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 0 }
      let(:user_score) { 40 }

      it 'includes low engagement insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Low engagement - consider re-engagement strategies')
      end
    end

    context 'when user has many unique actions' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 11 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 0 }
      let(:user_score) { 40 }

      it 'includes diverse activity profile insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Diverse activity profile across multiple action types')
      end
    end

    context 'when many patterns are detected' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 3 }
      let(:anomaly_count) { 0 }
      let(:user_score) { 40 }

      it 'includes behavioral patterns detected insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Clear behavioral patterns detected')
      end
    end

    context 'when anomalies are present' do
      let(:total_actions) { 50 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 2 }
      let(:user_score) { 40 }

      it 'includes anomalies detected insight with count' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('2 anomalous activities detected - review recommended')
      end
    end

    context 'when user is a power user' do
      let(:total_actions) { 150 }
      let(:unique_actions) { 5 }
      let(:pattern_count) { 1 }
      let(:anomaly_count) { 0 }
      let(:user_score) { 40 }

      it 'includes power user insight' do
        insights = reporter.send(:generate_insights, stats, patterns, user_score, anomalies)

        expect(insights).to include('Power user - high volume of activities')
      end
    end
  end

  describe '#parse_timestamp' do
    context 'when timestamp string is valid' do
      let(:timestamp_str) { '2024-01-01T10:00:00Z' }

      it 'parses the timestamp into a Time object' do
        result = reporter.send(:parse_timestamp, timestamp_str)

        expect(result).to be_a(Time)
        expect(result.iso8601).to eq(Time.parse(timestamp_str).iso8601)
      end
    end

    context 'when timestamp string is invalid' do
      let(:timestamp_str) { 'invalid-timestamp' }

      it 'returns current time when parsing fails' do
        allow(Time).to receive(:now).and_return(Time.new(2024, 1, 1, 0, 0, 0, '+00:00'))

        result = reporter.send(:parse_timestamp, timestamp_str)

        expect(result).to eq(Time.now)
      end
    end
  end

  describe '#error_report' do
    it 'returns an error hash with message and generated_at' do
      result = reporter.send(:error_report, 'Something went wrong')

      expect(result[:error]).to be true
      expect(result[:message]).to eq('Something went wrong')
      expect(result[:generated_at]).to be_a(String)
    end
  end
end
