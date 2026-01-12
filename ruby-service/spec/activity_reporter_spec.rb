require 'spec_helper'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:go_service_url) { 'http://go-service.test' }
  let(:python_service_url) { 'http://python-service.test' }
  let(:reporter) do
    described_class.new(
      go_service_url: go_service_url,
      python_service_url: python_service_url
    )
  end

  describe '#initialize' do
    it 'sets the service URLs' do
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
        { 'pattern_type' => 'daily', 'description' => 'Daily login', 'confidence' => 0.9 },
        { 'pattern_type' => 'weekly', 'description' => 'Weekly usage', 'confidence' => 0.8 }
      ]
    end
    let(:user_score) { 80.5 }
    let(:anomalies) do
      [
        { 'timestamp' => '2024-01-03T00:00:00Z', 'reason' => 'suspicious activity' }
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
      it 'returns a detailed report hash' do
        report = reporter.generate_report(user_id)

        expect(report[:user_id]).to eq(user_id)
        expect(report[:generated_at]).to eq('2024-01-10T12:00:00Z')
        expect(report[:summary]).to include(
          total_actions: 3,
          unique_actions: 3,
          engagement_score: user_score,
          first_activity: '2024-01-01T10:00:00Z',
          last_activity: '2024-01-02T09:30:00Z'
        )
        expect(report[:action_breakdown]).to eq(stats[:action_counts])
        expect(report[:patterns]).to all(include(:type, :description, :confidence))
        expect(report[:anomalies]).to eq(anomalies)
        expect(report[:timeline]).not_to be_empty
        expect(report[:insights]).to be_an(Array)
        expect(report[:insights]).not_to be_empty
      end

      it 'formats patterns using format_pattern' do
        report = reporter.generate_report(user_id)

        expect(report[:patterns]).to eq(
          patterns.map do |p|
            {
              type: p['pattern_type'],
              description: p['description'],
              confidence: p['confidence']
            }
          end
        )
      end

      it 'uses the provided group_by option for the timeline' do
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
        report = reporter.generate_report(user_id)

        expect(report[:error]).to be true
        expect(report[:message]).to eq('No activities found')
        expect(report[:generated_at]).to eq('2024-01-10T12:00:00Z')
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
        expect(periods).to include('2024-01-01 10:00', '2024-01-01 11:00', '2024-01-02 09:00')
      end
    end

    context 'when grouping by week' do
      it 'groups activities by ISO week' do
        result = reporter.format_timeline(activities, :week)

        expect(result.map { |r| r[:period] }).to all(eq('2024-W01'))
      end
    end

    context 'when grouping by month' do
      it 'groups activities by month' do
        result = reporter.format_timeline(activities, :month)

        expect(result.map { |r| r[:period] }).to all(eq('2024-01'))
      end
    end

    context 'when grouping by unknown period' do
      it 'defaults to grouping by day' do
        result = reporter.format_timeline(activities, :unknown)

        expect(result.size).to eq(2)
        expect(result.map { |r| r[:period] }).to contain_exactly('2024-01-01', '2024-01-02')
      end
    end

    context 'when timestamps are invalid' do
      let(:activities_with_invalid) do
        [
          { 'timestamp' => 'invalid-timestamp', 'action' => 'login' }
        ]
      end

      before do
        allow(Time).to receive(:now).and_return(Time.parse('2024-01-05T00:00:00Z'))
      end

      it 'uses current time for invalid timestamps via parse_timestamp' do
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

      it 'returns an error hash' do
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
        last_activity: '2024-01-01T11:00:00Z',
        most_frequent: 'login'
      }
    end
    let(:stats_user2) do
      {
        total_actions: 5,
        unique_actions: 2,
        action_counts: {},
        first_activity: '2024-01-01T11:00:00Z',
        last_activity: '2024-01-01T12:00:00Z',
        most_frequent: 'click'
      }
    end
    let(:stats_user3) do
      {
        total_actions: 20,
        unique_actions: 4,
        action_counts: {},
        first_activity: '2024-01-01T12:00:00Z',
        last_activity: '2024-01-01T13:00:00Z',
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
        result = reporter.compare_users([1])

        expect(result[:error]).to be true
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

        expect(result[:comparisons]).to include(
          hash_including(user_id: 1, total_actions: 10, engagement_score: 50.0, most_frequent_action: 'login'),
          hash_including(user_id: 2, total_actions: 5, engagement_score: 75.0, most_frequent_action: 'click'),
          hash_including(user_id: 3, total_actions: 20, engagement_score: 25.0, most_frequent_action: 'logout')
        )
      end

      it 'returns the top_user as the one with highest engagement_score' do
        result = reporter.compare_users(user_ids)

        expect(result[:top_user]).to eq(2)
      end

      it 'calculates the average_score correctly and rounds to 2 decimals' do
        result = reporter.compare_users(user_ids)

        expected_average = ((50.0 + 75.0 + 25.0) / 3.0).round(2)
        expect(result[:average_score]).to eq(expected_average)
      end
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

    it 'formats the pattern into a symbolized hash' do
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
    let(:patterns) { Array.new(pattern_count) { |i| { 'pattern_type' => "p#{i}" } } }
    let(:anomalies) { Array.new(anomaly_count) { |i| { id: i } } }

    let(:total_actions) { 10 }
    let(:unique_actions) { 5 }
    let(:pattern_count) { 0 }
    let(:anomaly_count) { 0 }
    let(:user_score) { 10.0 }

    subject(:insights) do
      reporter.send(:generate_insights, stats, patterns, user_score, anomalies)
    end

    context 'when user_score is low' do
      let(:user_score) { 10.0 }

      it 'includes low engagement insight' do
        expect(insights).to include('Low engagement - consider re-engagement strategies')
      end
    end

    context 'when user_score is moderately high' do
      let(:user_score) { 60.0 }

      it 'includes moderate engagement insight' do
        expect(insights).to include('Moderately engaged user with regular activity')
      end
    end

    context 'when user_score is very high' do
      let(:user_score) { 80.0 }

      it 'includes high engagement insight' do
        expect(insights).to include('Highly engaged user with strong activity patterns')
      end
    end

    context 'when unique_actions is greater than 10' do
      let(:unique_actions) { 11 }

      it 'includes diverse activity profile insight' do
        expect(insights).to include('Diverse activity profile across multiple action types')
      end
    end

    context 'when there are more than 2 patterns' do
      let(:pattern_count) { 3 }

      it 'includes behavioral patterns detected insight' do
        expect(insights).to include('Clear behavioral patterns detected')
      end
    end

    context 'when there are anomalies' do
      let(:anomaly_count) { 2 }

      it 'includes anomalies detected insight with count' do
        expect(insights).to include('2 anomalous activities detected - review recommended')
      end
    end

    context 'when total_actions is greater than 100' do
      let(:total_actions) { 150 }

      it 'includes power user insight' do
        expect(insights).to include('Power user - high volume of activities')
      end
    end
  end

  describe '#parse_timestamp' do
    context 'when timestamp is valid' do
      it 'parses the timestamp string into a Time object' do
        time = reporter.send(:parse_timestamp, '2024-01-01T10:00:00Z')

        expect(time).to be_a(Time)
        expect(time.utc.year).to eq(2024)
      end
    end

    context 'when timestamp is invalid' do
      before do
        allow(Time).to receive(:now).and_return(Time.parse('2024-01-05T00:00:00Z'))
      end

      it 'returns current time' do
        time = reporter.send(:parse_timestamp, 'invalid')

        expect(time).to eq(Time.parse('2024-01-05T00:00:00Z'))
      end
    end
  end

  describe '#error_report' do
    before do
      allow(Time).to receive(:now).and_return(Time.parse('2024-01-10T12:00:00Z'))
    end

    it 'returns an error hash with message and timestamp' do
      result = reporter.send(:error_report, 'Something went wrong')

      expect(result[:error]).to be true
      expect(result[:message]).to eq('Something went wrong')
      expect(result[:generated_at]).to eq('2024-01-10T12:00:00Z')
    end
  end
end
