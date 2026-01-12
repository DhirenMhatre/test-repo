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
        { 'timestamp' => '2024-01-02T09:00:00Z', 'action' => 'logout' }
      ]
    end

    let(:stats) do
      {
        total_actions: 3,
        unique_actions: 3,
        action_counts: { 'login' => 1, 'click' => 1, 'logout' => 1 },
        first_activity: '2024-01-01T10:00:00Z',
        last_activity: '2024-01-02T09:00:00Z',
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
        expect(report[:patterns].map { |p| p[:type] }).to match_array(%w[daily weekly])

        expect(report[:anomalies]).to eq(anomalies)

        expect(report[:timeline]).to be_an(Array)
        expect(report[:insights]).to be_an(Array)
        expect(report[:insights]).not_to be_empty
      end

      it 'groups timeline by default by day' do
        report = reporter.generate_report(user_id)
        periods = report[:timeline].map { |t| t[:period] }

        expect(periods).to eq(%w[2024-01-01 2024-01-02])
      end

      it 'respects the group_by option for timeline' do
        report = reporter.generate_report(user_id, group_by: :month)
        periods = report[:timeline].map { |t| t[:period] }

        expect(periods).to eq(['2024-01'])
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
        { 'timestamp' => '2024-01-01T10:45:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-01-01T11:00:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-01-02T09:00:00Z', 'action' => 'logout' }
      ]
    end

    context 'when activities array is empty' do
      it 'returns an empty array' do
        result = reporter.format_timeline([])
        expect(result).to eq([])
      end
    end

    context 'when grouping by hour' do
      it 'groups activities by hour and counts actions' do
        result = reporter.format_timeline(activities, :hour)

        expect(result.size).to eq(3)
        periods = result.map { |r| r[:period] }
        expect(periods).to eq(
          [
            '2024-01-01 10:00',
            '2024-01-01 11:00',
            '2024-01-02 09:00'
          ]
        )

        first_period = result.find { |r| r[:period] == '2024-01-01 10:00' }
        expect(first_period[:total_actions]).to eq(2)
        expect(first_period[:actions]).to eq('login' => 1, 'click' => 1)
        expect(first_period[:first_timestamp]).to eq('2024-01-01T10:15:00Z')
        expect(first_period[:last_timestamp]).to eq('2024-01-01T10:45:00Z')
      end
    end

    context 'when grouping by day' do
      it 'groups activities by day' do
        result = reporter.format_timeline(activities, :day)

        expect(result.size).to eq(2)
        expect(result.map { |r| r[:period] }).to eq(%w[2024-01-01 2024-01-02])
      end
    end

    context 'when grouping by week' do
      it 'groups activities by ISO week' do
        result = reporter.format_timeline(activities, :week)

        expect(result.size).to eq(1)
        expect(result.first[:period]).to eq('2024-W01')
        expect(result.first[:total_actions]).to eq(4)
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

        expect(result.size).to eq(2)
        expect(result.map { |r| r[:period] }).to eq(%w[2024-01-01 2024-01-02])
      end
    end

    context 'when timestamps are invalid' do
      let(:activities_with_invalid) do
        [
          { 'timestamp' => 'invalid-timestamp', 'action' => 'login' }
        ]
      end

      it 'falls back to current time without raising error' do
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
      let(:filepath) do
        'tmp/test_report.json'
      end

      before do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      end

      it 'returns an error hash with message' do
        result = reporter.export_to_json(report, filepath)

        expect(result[:success]).to eq(false)
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users([1])

        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
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
          unique_actions: 2,
          action_counts: { 'login' => 8, 'click' => 2 },
          first_activity: '2024-01-01T10:00:00Z',
          last_activity: '2024-01-02T10:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:stats_user2) do
        {
          total_actions: 5,
          unique_actions: 1,
          action_counts: { 'click' => 5 },
          first_activity: '2024-01-01T11:00:00Z',
          last_activity: '2024-01-02T11:00:00Z',
          most_frequent: 'click'
        }
      end

      let(:stats_user3) do
        {
          total_actions: 20,
          unique_actions: 3,
          action_counts: { 'logout' => 10, 'login' => 5, 'click' => 5 },
          first_activity: '2024-01-01T12:00:00Z',
          last_activity: '2024-01-03T12:00:00Z',
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

        scores = result[:comparisons].map { |c| c[:engagement_score] }
        expect(scores).to eq([90.0, 60.0, 40.0])

        expect(result[:top_user]).to eq(3)

        expected_average = ((90.0 + 60.0 + 40.0) / 3.0).round(2)
        expect(result[:average_score]).to eq(expected_average)

        first_comp = result[:comparisons].first
        expect(first_comp).to include(
          user_id: 3,
          total_actions: stats_user3[:total_actions],
          engagement_score: 90.0,
          most_frequent_action: stats_user3[:most_frequent]
        )
      end
    end
  end
end
