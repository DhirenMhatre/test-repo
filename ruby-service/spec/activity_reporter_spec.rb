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
    it 'initializes with default URLs when none are provided' do
      instance = described_class.new
      expect(instance.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
      expect(instance.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
    end

    it 'initializes with custom URLs when provided' do
      expect(reporter.instance_variable_get(:@go_service_url)).to eq(go_service_url)
      expect(reporter.instance_variable_get(:@python_service_url)).to eq(python_service_url)
    end
  end

  describe '#generate_report' do
    let(:user_id) do
      123
    end

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

    let(:user_score) do
      80.0
    end

    let(:anomalies) do
      [
        { 'timestamp' => '2024-01-03T00:00:00Z', 'action' => 'suspicious' }
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
        expect(result[:generated_at]).to eq('2024-01-10T12:00:00Z')
      end
    end

    context 'when user has activities' do
      it 'returns a report with summary, patterns, anomalies, timeline and insights' do
        result = reporter.generate_report(user_id)

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

        expect(result[:patterns]).to eq(
          [
            { type: 'daily', description: 'Daily login', confidence: 0.9 },
            { type: 'weekly', description: 'Weekly usage', confidence: 0.8 }
          ]
        )

        expect(result[:anomalies]).to eq(anomalies)

        expect(result[:timeline]).to be_an(Array)
        expect(result[:timeline].size).to be >= 1

        expect(result[:insights]).to be_an(Array)
        expect(result[:insights]).not_to be_empty
      end

      it 'passes group_by option to format_timeline' do
        expect(reporter).to receive(:format_timeline).with(activities, :hour).and_call_original
        reporter.generate_report(user_id, group_by: :hour)
      end

      it 'uses default group_by :day when not provided' do
        expect(reporter).to receive(:format_timeline).with(activities, :day).and_call_original
        reporter.generate_report(user_id)
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

    context 'when activities list is empty' do
      it 'returns an empty array' do
        result = reporter.format_timeline([])
        expect(result).to eq([])
      end
    end

    context 'when grouping by day' do
      it 'groups activities by day and aggregates counts' do
        result = reporter.format_timeline(activities, :day)
        expect(result.size).to eq(2)

        day1 = result.find do |entry|
          entry[:period] == '2024-01-01'
        end
        day2 = result.find do |entry|
          entry[:period] == '2024-01-02'
        end

        expect(day1[:total_actions]).to eq(3)
        expect(day1[:actions]).to eq('login' => 1, 'click' => 2)
        expect(day1[:first_timestamp]).to eq('2024-01-01T10:15:00Z')
        expect(day1[:last_timestamp]).to eq('2024-01-01T11:00:00Z')

        expect(day2[:total_actions]).to eq(1)
        expect(day2[:actions]).to eq('logout' => 1)
      end
    end

    context 'when grouping by hour' do
      it 'groups activities by hour' do
        result = reporter.format_timeline(activities, :hour)
        periods = result.map do |entry|
          entry[:period]
        end
        expect(periods).to include('2024-01-01 10:00', '2024-01-01 11:00', '2024-01-02 09:00')

        hour_10 = result.find do |entry|
          entry[:period] == '2024-01-01 10:00'
        end
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

    context 'when grouping by unknown key' do
      it 'falls back to grouping by day' do
        result = reporter.format_timeline(activities, :unknown)
        periods = result.map do |entry|
          entry[:period]
        end
        expect(periods).to contain_exactly('2024-01-01', '2024-01-02')
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
        summary: {
          total_actions: 5
        }
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
      let(:filepath) do
        'tmp/test_report.json'
      end

      before do
        allow(File).to receive(:write).and_return(100)
      end

      it 'writes JSON to the file and returns metadata' do
        result = reporter.export_to_json(report, filepath)
        expect(File).to have_received(:write).with(filepath, kind_of(String))
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(filepath)
        expect(result[:size]).to be > 0
      end
    end

    context 'when an error occurs during file write' do
      let(:filepath) do
        'tmp/test_report.json'
      end

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
    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        allow(Time).to receive(:now).and_return(Time.parse('2024-01-10T12:00:00Z'))
        result = reporter.compare_users([1])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq('2024-01-10T12:00:00Z')
      end
    end

    context 'when two or more users are provided' do
      let(:user_ids) do
        [1, 2, 3]
      end

      let(:activities_user1) do
        [{ 'timestamp' => '2024-01-01T10:00:00Z', 'action' => 'login' }]
      end

      let(:activities_user2) do
        [{ 'timestamp' => '2024-01-01T11:00:00Z', 'action' => 'click' }]
      end

      let(:activities_user3) do
        [{ 'timestamp' => '2024-01-01T12:00:00Z', 'action' => 'logout' }]
      end

      let(:stats_user1) do
        {
          total_actions: 10,
          unique_actions: 3,
          action_counts: {},
          first_activity: '2024-01-01T10:00:00Z',
          last_activity: '2024-01-01T10:30:00Z',
          most_frequent: 'login'
        }
      end

      let(:stats_user2) do
        {
          total_actions: 5,
          unique_actions: 2,
          action_counts: {},
          first_activity: '2024-01-01T11:00:00Z',
          last_activity: '2024-01-01T11:30:00Z',
          most_frequent: 'click'
        }
      end

      let(:stats_user3) do
        {
          total_actions: 20,
          unique_actions: 4,
          action_counts: {},
          first_activity: '2024-01-01T12:00:00Z',
          last_activity: '2024-01-01T12:30:00Z',
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

        allow(reporter).to receive(:fetch_user_score).with(activities_user1).and_return(60.0)
        allow(reporter).to receive(:fetch_user_score).with(activities_user2).and_return(40.0)
        allow(reporter).to receive(:fetch_user_score).with(activities_user3).and_return(90.0)
      end

      it 'returns comparisons sorted by engagement_score descending' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].size).to eq(3)

        scores = result[:comparisons].map do |c|
          c[:engagement_score]
        end
        expect(scores).to eq([90.0, 60.0, 40.0])

        expect(result[:top_user]).to eq(3)
      end

      it 'calculates the average engagement score' do
        result = reporter.compare_users(user_ids)
        expect(result[:average_score]).to eq(((90.0 + 60.0 + 40.0) / 3.0).round(2))
      end

      it 'includes most_frequent_action for each user' do
        result = reporter.compare_users(user_ids)
        most_frequents = result[:comparisons].map do |c|
          c[:most_frequent_action]
        end
        expect(most_frequents).to contain_exactly('login', 'click', 'logout')
      end
    end
  end
end
