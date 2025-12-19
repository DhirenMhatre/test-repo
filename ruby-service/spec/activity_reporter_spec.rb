require 'spec_helper'
require 'tmpdir'
require 'rails_helper'

RSpec.describe ActivityReporter do
  describe '#initialize' do
    it 'sets default service URLs' do
      instance = described_class.new
      expect(instance.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
      expect(instance.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
    end

    it 'allows custom service URLs' do
      instance = described_class.new(go_service_url: 'http://go.example', python_service_url: 'http://py.example')
      expect(instance.instance_variable_get(:@go_service_url)).to eq('http://go.example')
      expect(instance.instance_variable_get(:@python_service_url)).to eq('http://py.example')
    end
  end

  describe '#generate_report' do
    let(:reporter) { described_class.new }
    let(:now) { Time.utc(2025, 1, 20, 12, 34, 56) }

    before do
      allow(Time).to receive(:now).and_return(now)
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(123).and_return([])
      end

      it 'returns an error report' do
        result = reporter.generate_report(123)
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(now.iso8601)
      end
    end

    context 'with activities present' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-10T10:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-10T11:00:00Z', 'action' => 'view' }
        ]
      end

      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 12,
          action_counts: { 'login' => 100, 'view' => 50 },
          first_activity: '2025-01-01T00:00:00Z',
          last_activity: '2025-01-15T00:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'sequence', 'description' => 'daily login', 'confidence' => 0.9 },
          { 'pattern_type' => 'time_of_day', 'description' => 'morning active', 'confidence' => 0.8 },
          { 'pattern_type' => 'frequency', 'description' => 'high frequency', 'confidence' => 0.85 }
        ]
      end

      let(:formatted_patterns) do
        [
          { type: 'sequence', description: 'daily login', confidence: 0.9 },
          { type: 'time_of_day', description: 'morning active', confidence: 0.8 },
          { type: 'frequency', description: 'high frequency', confidence: 0.85 }
        ]
      end

      let(:user_score) { 82.5 }
      let(:anomalies) { [{ 'id' => 1 }, { 'id' => 2 }] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(123).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(123).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a comprehensive report with formatted patterns and insights' do
        result = reporter.generate_report(123)

        expect(result[:user_id]).to eq(123)
        expect(result[:generated_at]).to eq(now.iso8601)

        expect(result[:summary][:total_actions]).to eq(150)
        expect(result[:summary][:unique_actions]).to eq(12)
        expect(result[:summary][:engagement_score]).to eq(82.5)
        expect(result[:summary][:first_activity]).to eq('2025-01-01T00:00:00Z')
        expect(result[:summary][:last_activity]).to eq('2025-01-15T00:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'login' => 100, 'view' => 50 })
        expect(result[:patterns]).to eq(formatted_patterns)
        expect(result[:anomalies]).to eq(anomalies)

        expected_insights = [
          'Highly engaged user with strong activity patterns',
          'Diverse activity profile across multiple action types',
          'Clear behavioral patterns detected',
          '2 anomalous activities detected - review recommended',
          'Power user - high volume of activities'
        ]
        expected_insights.each do |insight|
          expect(result[:insights]).to include(insight)
        end
      end

      it 'passes group_by option to format_timeline' do
        expect(reporter).to receive(:format_timeline).with(activities, :hour).and_return([])
        result = reporter.generate_report(123, { group_by: :hour })
        expect(result[:timeline]).to eq([])
      end

      it 'includes a timeline grouped by day by default' do
        result = reporter.generate_report(123)
        expect(result[:timeline]).to be_a(Array)
        expect(result[:timeline]).not_to be_empty
        expect(result[:timeline].first).to have_key(:period)
        expect(result[:timeline].first).to have_key(:actions)
      end

      it 'includes only the low engagement insight when scores and metrics are low' do
        allow(reporter).to receive(:fetch_activity_stats).with(123).and_return(
          {
            total_actions: 5,
            unique_actions: 2,
            action_counts: { 'login' => 3, 'view' => 2 },
            first_activity: '2025-01-01T00:00:00Z',
            last_activity: '2025-01-02T00:00:00Z',
            most_frequent: 'login'
          }
        )
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return([])
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(10.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([])

        result = reporter.generate_report(123)
        expect(result[:insights]).to include('Low engagement - consider re-engagement strategies')
        expect(result[:insights].length).to eq(1)
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) { described_class.new }

    context 'when activities are empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([])).to eq([])
      end
    end

    context 'grouping by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-15T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-15T10:45:00Z', 'action' => 'view' },
          { 'timestamp' => '2025-01-15T11:05:00Z', 'action' => 'click' }
        ]
      end

      it 'groups into hourly buckets with action counts' do
        timeline = reporter.format_timeline(activities, :hour)
        expect(timeline.size).to eq(2)

        first = timeline[0]
        second = timeline[1]

        expect(first[:period]).to eq('2025-01-15 10:00')
        expect(first[:total_actions]).to eq(2)
        expect(first[:actions]).to eq({ 'login' => 1, 'view' => 1 })
        expect(first[:first_timestamp]).to eq('2025-01-15T10:15:00Z')
        expect(first[:last_timestamp]).to eq('2025-01-15T10:45:00Z')

        expect(second[:period]).to eq('2025-01-15 11:00')
        expect(second[:total_actions]).to eq(1)
        expect(second[:actions]).to eq({ 'click' => 1 })
      end
    end

    context 'grouping by day (default and invalid group_by)' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-02T09:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-02T12:00:00Z', 'action' => 'view' }
        ]
      end

      it 'groups by day by default' do
        timeline = reporter.format_timeline(activities)
        expect(timeline.size).to eq(1)
        expect(timeline.first[:period]).to eq('2025-01-02')
        expect(timeline.first[:actions]).to eq({ 'login' => 1, 'view' => 1 })
      end

      it 'falls back to day when group_by is invalid' do
        timeline = reporter.format_timeline(activities, :unknown)
        expect(timeline.size).to eq(1)
        expect(timeline.first[:period]).to eq('2025-01-02')
      end
    end

    context 'grouping by week and month' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-01T10:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2025-01-08T10:00:00Z', 'action' => 'b' },
          { 'timestamp' => '2025-02-01T10:00:00Z', 'action' => 'c' }
        ]
      end

      it 'groups by week using ISO week numbers' do
        timeline = reporter.format_timeline(activities, :week)
        periods = timeline.map { |t| t[:period] }
        expect(periods).to include('2025-W01')
        expect(periods).to include('2025-W02')
      end

      it 'groups by month' do
        timeline = reporter.format_timeline(activities, :month)
        periods = timeline.map { |t| t[:period] }
        expect(periods).to include('2025-01')
        expect(periods).to include('2025-02')
      end
    end

    context 'handles invalid timestamps by using current time' do
      let(:now) { Time.utc(2025, 1, 1, 0, 0, 0) }

      before do
        allow(Time).to receive(:now).and_return(now)
      end

      it 'uses Time.now when parsing fails and preserves original timestamps in entries' do
        activities = [{ 'timestamp' => 'invalid', 'action' => 'login' }]
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.size).to eq(1)
        expect(timeline.first[:period]).to eq('2025-01-01')
        expect(timeline.first[:first_timestamp]).to eq('invalid')
        expect(timeline.first[:last_timestamp]).to eq('invalid')
      end
    end
  end

  describe '#export_to_json' do
    let(:reporter) { described_class.new }
    let(:report) do
      {
        user_id: 1,
        generated_at: '2025-01-20T12:00:00Z',
        summary: { total_actions: 3, unique_actions: 2, engagement_score: 10.5, first_activity: '2025-01-01T00:00:00Z',
                   last_activity: '2025-01-02T00:00:00Z' },
        action_breakdown: { 'a' => 2, 'b' => 1 },
        patterns: [],
        anomalies: [],
        timeline: [],
        insights: []
      }
    end

    it 'returns pretty JSON data when no filepath is provided' do
      result = reporter.export_to_json(report)
      expect(result[:success]).to be true
      json = result[:data]
      parsed = JSON.parse(json)
      expect(parsed).to eq(JSON.parse(JSON.pretty_generate(report)))
    end

    it 'writes JSON to the given filepath and returns metadata' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(report, path)
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(path)
        expect(File.exist?(path)).to be true
        content = File.read(path)
        expect(JSON.parse(content)).to eq(JSON.parse(JSON.pretty_generate(report)))
        expect(result[:size]).to eq(JSON.pretty_generate(report).bytesize)
      end
    end

    it 'returns an error hash when writing fails' do
      allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(report, path)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    let(:reporter) { described_class.new }
    let(:now) { Time.utc(2025, 1, 20, 12, 0, 0) }

    before do
      allow(Time).to receive(:now).and_return(now)
    end

    context 'when fewer than 2 user ids are provided' do
      it 'returns an error report' do
        result = reporter.compare_users([1])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(now.iso8601)
      end
    end

    context 'with multiple users' do
      let(:user_ids) { [1, 2, 3] }

      before do
        allow(reporter).to receive(:fetch_user_activities) do |uid|
          [{ 'dummy' => uid }]
        end

        allow(reporter).to receive(:fetch_activity_stats) do |uid|
          {
            total_actions: uid * 10,
            unique_actions: uid + 1,
            action_counts: { 'x' => uid },
            first_activity: "2025-01-0#{uid}T00:00:00Z",
            last_activity: "2025-01-1#{uid}T00:00:00Z",
            most_frequent: "action_#{uid}"
          }
        end

        allow(reporter).to receive(:fetch_user_score) do |activities|
          activities.first['dummy'] * 10.0
        end
      end

      it 'returns sorted comparisons by engagement score with top_user and average_score' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        comparisons = result[:comparisons]
        expect(comparisons.map { |c| c[:user_id] }).to eq([3, 2, 1])
        expect(comparisons.map { |c| c[:engagement_score] }).to eq([30.0, 20.0, 10.0])
        expect(comparisons.map { |c| c[:total_actions] }).to eq([30, 20, 10])
        expect(comparisons.map { |c| c[:most_frequent] }).to eq(%w[action_3 action_2 action_1])

        expect(result[:top_user]).to eq(3)
        expect(result[:average_score]).to eq(((30.0 + 20.0 + 10.0) / 3.0).round(2))
      end

      it 'keeps stable ordering for equal scores' do
        allow(reporter).to receive(:fetch_user_score).and_return(50.0)
        result = reporter.compare_users([10, 20])
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq([10, 20])
        expect(result[:top_user]).to eq(10)
      end
    end
  end
end
