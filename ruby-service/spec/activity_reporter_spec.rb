require 'spec_helper'
require 'json'
require 'rails_helper'

RSpec.describe ActivityReporter do
  let(:reporter) { described_class.new }
  let(:now) { Time.utc(2024, 1, 2, 3, 4, 5) }

  before do
    allow(Time).to receive(:now).and_return(now)
  end

  describe '#initialize' do
    it 'allows custom service URLs without error' do
      expect do
        described_class.new(go_service_url: 'http://go', python_service_url: 'http://py')
      end.not_to raise_error
    end
  end

  describe '#generate_report' do
    let(:user_id) { 'user-123' }

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report with message and timestamp' do
        result = reporter.generate_report(user_id)
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(now.iso8601)
      end
    end

    context 'when activities are present' do
      let(:activities) do
        [
          { 'timestamp' => '2023-12-29T10:30:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-01-02T12:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2024-01-02T12:15:00Z', 'action' => 'view' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 3,
          action_counts: { 'login' => 1, 'click' => 1, 'view' => 1 },
          first_activity: '2023-12-29T10:30:00Z',
          last_activity: '2024-01-02T12:15:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'streak', 'description' => 'Daily active', 'confidence' => 0.9 }
        ]
      end

      let(:anomalies) do
        [
          { 'type' => 'suspicious_login' },
          { 'type' => 'geo_mismatch' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(82.5)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a comprehensive report with summary, breakdown, patterns, anomalies, timeline and insights' do
        result = reporter.generate_report(user_id, group_by: :week)
        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(now.iso8601)

        expect(result[:summary][:total_actions]).to eq(stats[:total_actions])
        expect(result[:summary][:unique_actions]).to eq(stats[:unique_actions])
        expect(result[:summary][:engagement_score]).to eq(82.5)
        expect(result[:summary][:first_activity]).to eq(stats[:first_activity])
        expect(result[:summary][:last_activity]).to eq(stats[:last_activity])

        expect(result[:action_breakdown]).to eq(stats[:action_counts])

        expect(result[:patterns]).to eq([{ type: 'streak', description: 'Daily active', confidence: 0.9 }])

        expect(result[:anomalies]).to eq(anomalies)

        periods = result[:timeline].map { |e| e[:period] }
        expect(periods).to include('2023-W52')
        expect(periods).to include('2024-W01')

        insights = result[:insights]
        expect(insights.any? { |i| i.include?('Highly engaged user') }).to eq(true)
        expect(insights).to include('2 anomalous activities detected - review recommended')
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities array is empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([])).to eq([])
      end
    end

    context 'when grouping by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-01T15:05:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-01-01T15:45:00Z', 'action' => 'click' }
        ]
      end

      it 'groups activities into hourly buckets with counts' do
        timeline = reporter.format_timeline(activities, :hour)
        expect(timeline.size).to eq(1)
        entry = timeline.first
        expect(entry[:period]).to eq('2024-01-01 15:00')
        expect(entry[:total_actions]).to eq(2)
        expect(entry[:actions]).to eq({ 'login' => 1, 'click' => 1 })
        expect(entry[:first_timestamp]).to eq('2024-01-01T15:05:00Z')
        expect(entry[:last_timestamp]).to eq('2024-01-01T15:45:00Z')
      end
    end

    context 'when grouping by day' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-02T10:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2024-01-02T11:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2024-01-03T09:00:00Z', 'action' => 'click' }
        ]
      end

      it 'groups activities into day buckets and sorts by period' do
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.map { |e| e[:period] }).to eq(%w[2024-01-02 2024-01-03])
        day_one = timeline[0]
        expect(day_one[:total_actions]).to eq(2)
        expect(day_one[:actions]).to eq({ 'view' => 2 })
      end
    end

    context 'when grouping by week' do
      let(:activities) do
        [
          { 'timestamp' => '2023-12-31T23:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-01-01T01:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2024-01-08T12:00:00Z', 'action' => 'view' }
        ]
      end

      it 'groups activities into ISO week buckets' do
        timeline = reporter.format_timeline(activities, :week)
        periods = timeline.map { |e| e[:period] }
        expect(periods).to include('2023-W52').or include('2023-W53')
        expect(periods).to include('2024-W01')
        expect(periods).to include('2024-W02')
      end
    end

    context 'when grouping by month' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-15T10:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2024-01-20T10:00:00Z', 'action' => 'b' },
          { 'timestamp' => '2024-02-01T10:00:00Z', 'action' => 'a' }
        ]
      end

      it 'groups activities into monthly buckets' do
        timeline = reporter.format_timeline(activities, :month)
        expect(timeline.map { |e| e[:period] }).to eq(%w[2024-01 2024-02])
        jan = timeline.first
        expect(jan[:total_actions]).to eq(2)
        expect(jan[:actions]).to eq({ 'a' => 1, 'b' => 1 })
      end
    end

    context 'when group_by is unknown' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-10T10:00:00Z', 'action' => 'x' },
          { 'timestamp' => '2024-01-10T11:00:00Z', 'action' => 'y' }
        ]
      end

      it 'falls back to day grouping' do
        timeline = reporter.format_timeline(activities, :unknown)
        expect(timeline.size).to eq(1)
        expect(timeline.first[:period]).to eq('2024-01-10')
      end
    end

    context 'when an activity has an invalid timestamp' do
      let(:activities) do
        [
          { 'timestamp' => 'invalid', 'action' => 'broken' },
          { 'timestamp' => '2024-01-01T00:00:00Z', 'action' => 'ok' }
        ]
      end

      it 'parses invalid timestamp as current time and groups accordingly' do
        timeline = reporter.format_timeline(activities, :day)
        periods = timeline.map { |e| e[:period] }
        expect(periods).to include(now.strftime('%Y-%m-%d'))
        expect(periods).to include('2024-01-01')
      end
    end

    context 'when entries within the same group are in reverse order' do
      let(:activities) do
        [
          { 'timestamp' => '2024-01-05T12:00:00Z', 'action' => 'late' },
          { 'timestamp' => '2024-01-05T08:00:00Z', 'action' => 'early' }
        ]
      end

      it 'preserves first and last timestamps based on original order' do
        timeline = reporter.format_timeline(activities, :day)
        entry = timeline.first
        expect(entry[:first_timestamp]).to eq('2024-01-05T12:00:00Z')
        expect(entry[:last_timestamp]).to eq('2024-01-05T08:00:00Z')
      end
    end
  end

  describe '#export_to_json' do
    let(:report_hash) do
      {
        user_id: 'u1',
        summary: { total_actions: 1 },
        timeline: []
      }
    end

    context 'when no filepath is provided' do
      it 'returns JSON data as a string' do
        result = reporter.export_to_json(report_hash)
        expect(result[:success]).to eq(true)
        expect(result[:data]).to be_a(String)
        expect(result[:data]).to include('"user_id"')
      end
    end

    context 'when a filepath is provided' do
      let(:filepath) { '/tmp/report.json' }

      it 'writes the file and returns the path and size' do
        expected_size = JSON.pretty_generate(report_hash).bytesize
        expect(File).to receive(:write).with(filepath, kind_of(String)).and_return(expected_size)
        result = reporter.export_to_json(report_hash, filepath)
        expect(result[:success]).to eq(true)
        expect(result[:filepath]).to eq(filepath)
        expect(result[:size]).to eq(expected_size)
      end
    end

    context 'when file writing raises an error' do
      let(:filepath) { '/tmp/report.json' }

      it 'returns a failure hash with the error message' do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        result = reporter.export_to_json(report_hash, filepath)
        expect(result[:success]).to eq(false)
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(now.iso8601)
      end
    end

    context 'with multiple users' do
      let(:user_ids) { %w[u1 u2 u3] }

      before do
        allow(reporter).to receive(:fetch_user_activities).and_return(
          [{ 'uid' => 'u1' }],
          [{ 'uid' => 'u2' }],
          [{ 'uid' => 'u3' }]
        )
        allow(reporter).to receive(:fetch_activity_stats).and_return(
          { total_actions: 10, unique_actions: 3, action_counts: {}, first_activity: now.iso8601,
            last_activity: now.iso8601, most_frequent: 'login' },
          { total_actions: 5, unique_actions: 2, action_counts: {}, first_activity: now.iso8601,
            last_activity: now.iso8601, most_frequent: 'click' },
          { total_actions: 20, unique_actions: 4, action_counts: {}, first_activity: now.iso8601,
            last_activity: now.iso8601, most_frequent: 'view' }
        )
        allow(reporter).to receive(:fetch_user_score).and_return(75.0, 60.0, 90.0)
      end

      it 'returns sorted comparisons, top_user and average_score' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[u3 u1 u2])
        expect(result[:comparisons].map { |c| c[:engagement_score] }).to eq([90.0, 75.0, 60.0])
        expect(result[:comparisons].map { |c| c[:most_frequent_action] }).to eq(%w[view login click])
        expect(result[:top_user]).to eq('u3')
        expect(result[:average_score]).to eq(((90.0 + 75.0 + 60.0) / 3.0).round(2))
      end
    end
  end
end
