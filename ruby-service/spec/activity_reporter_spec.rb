require 'spec_helper'
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
        { 'pattern_type' => 'daily', 'description' => 'Logs in daily', 'confidence' => 0.9 },
        { 'pattern_type' => 'morning', 'description' => 'Active in the morning', 'confidence' => 0.8 }
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
      it 'returns a structured report with expected keys' do
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
        expect(report[:patterns].map { |p| p[:type] }).to match_array(patterns.map { |p| p['pattern_type'] })

        expect(report[:anomalies]).to eq(anomalies)

        expect(report[:timeline]).to be_an(Array)
        expect(report[:insights]).to be_an(Array)
        expect(report[:insights]).not_to be_empty
      end

      it 'groups timeline by day by default' do
        report = reporter.generate_report(user_id)
        periods = report[:timeline].map { |t| t[:period] }

        expect(periods).to include('2024-01-01', '2024-01-02')
      end

      it 'respects the group_by option for timeline' do
        report = reporter.generate_report(user_id, group_by: :month)
        periods = report[:timeline].map { |t| t[:period] }.uniq

        expect(periods).to eq(['2024-01'])
      end
    end

    context 'when no activities exist' do
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

    context 'when grouping by hour' do
      it 'groups activities into hourly buckets with counts' do
        result = reporter.format_timeline(activities, :hour)

        expect(result).to be_an(Array)
        expect(result.size).to eq(3)

        first_period = result.find { |r| r[:period] == '2024-01-01 10:00' }
        expect(first_period[:total_actions]).to eq(2)
        expect(first_period[:actions]).to eq('login' => 1, 'click' => 1)
      end
    end

    context 'when grouping by day' do
      it 'groups activities into daily buckets' do
        result = reporter.format_timeline(activities, :day)

        expect(result.size).to eq(2)
        day1 = result.find { |r| r[:period] == '2024-01-01' }
        day2 = result.find { |r| r[:period] == '2024-01-02' }

        expect(day1[:total_actions]).to eq(3)
        expect(day2[:total_actions]).to eq(1)
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

        expect(result.size).to eq(2)
        expect(result.map { |r| r[:period] }).to include('2024-01-01', '2024-01-02')
      end
    end

    context 'when timestamps are invalid' do
      let(:activities_with_invalid) do
        [
          { 'timestamp' => 'invalid-timestamp', 'action' => 'login' }
        ]
      end

      it 'falls back to current time without raising an error' do
        expect do
          reporter.format_timeline(activities_with_invalid, :day)
        end.not_to raise_error
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
      let(:filepath) do
        'tmp/test_report.json'
      end

      before do
        allow(File).to receive(:write).and_call_original
      end

      after do
        File.delete(filepath) if File.exist?(filepath)
      end

      it 'writes JSON to the file and returns metadata' do
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

      it 'returns an error hash' do
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

        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'when multiple users are provided' do
      it 'returns comparisons sorted by engagement score descending' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].size).to eq(3)

        scores = result[:comparisons].map { |c| c[:engagement_score] }
        expect(scores).to eq(scores.sort.reverse)

        expect(result[:top_user]).to eq(2)
      end

      it 'calculates the average engagement score' do
        result = reporter.compare_users(user_ids)

        expect(result[:average_score]).to eq(((50.0 + 75.0 + 25.0) / 3.0).round(2))
      end

      it 'includes expected fields for each user comparison' do
        result = reporter.compare_users(user_ids)
        comparison = result[:comparisons].find { |c| c[:user_id] == 1 }

        expect(comparison[:total_actions]).to eq(stats_user1[:total_actions])
        expect(comparison[:engagement_score]).to eq(50.0)
        expect(comparison[:most_frequent_action]).to eq('login')
      end
    end
  end
end
