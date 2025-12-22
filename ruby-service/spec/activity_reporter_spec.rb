require 'spec_helper'
require 'tmpdir'
require 'rails_helper'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new
  end

  describe '#generate_report' do
    context 'when no activities found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([])
      end

      it 'returns an error report' do
        result = reporter.generate_report('u1')
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with activities and stats' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T10:00:00Z' },
          { 'action' => 'purchase', 'timestamp' => '2025-01-01T12:00:00Z' },
          { 'action' => 'login', 'timestamp' => '2025-01-02T09:30:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 2,
          action_counts: { 'login' => 2, 'purchase' => 1 },
          first_activity: '2025-01-01T10:00:00Z',
          last_activity: '2025-01-02T12:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'daily_routine', 'description' => 'Logs in every morning', 'confidence' => 0.9 }
        ]
      end

      let(:anomalies) do
        [{ 'type' => 'suspicious_login' }]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(80.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'returns a comprehensive report with expected fields' do
        result = reporter.generate_report('u1', group_by: :day)
        expect(result[:user_id]).to eq('u1')
        expect(result[:summary][:total_actions]).to eq(3)
        expect(result[:summary][:unique_actions]).to eq(2)
        expect(result[:summary][:engagement_score]).to eq(80.0)
        expect(result[:action_breakdown]).to eq(stats[:action_counts])
        expect(result[:patterns]).to eq([{ type: 'daily_routine', description: 'Logs in every morning',
                                           confidence: 0.9 }])
        expect(result[:anomalies]).to eq(anomalies)
        expect(result[:timeline].map { |e| e[:period] }).to include('2025-01-01', '2025-01-02')
        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights].any? { |s| s.include?('anomalous activities') }).to be true
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities are empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([], :day)).to eq([])
      end
    end

    context 'grouping by hour' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T10:15:00Z' },
          { 'action' => 'login', 'timestamp' => '2025-01-01T10:45:00Z' },
          { 'action' => 'purchase', 'timestamp' => '2025-01-01T11:00:00Z' }
        ]
      end

      it 'groups into hourly buckets with action counts' do
        timeline = reporter.format_timeline(activities, :hour)
        expect(timeline.length).to eq(2)
        expect(timeline[0][:period]).to eq('2025-01-01 10:00')
        expect(timeline[0][:total_actions]).to eq(2)
        expect(timeline[0][:actions]).to eq({ 'login' => 2 })
        expect(timeline[0][:first_timestamp]).to eq('2025-01-01T10:15:00Z')
        expect(timeline[0][:last_timestamp]).to eq('2025-01-01T10:45:00Z')
        expect(timeline[1][:period]).to eq('2025-01-01 11:00')
        expect(timeline[1][:actions]).to eq({ 'purchase' => 1 })
      end
    end

    context 'grouping by day' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T23:50:00Z' },
          { 'action' => 'purchase', 'timestamp' => '2025-01-02T00:05:00Z' }
        ]
      end

      it 'groups into daily buckets' do
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.map { |e| e[:period] }).to eq(%w[2025-01-01 2025-01-02])
      end
    end

    context 'grouping by week' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T00:00:00Z' },
          { 'action' => 'purchase', 'timestamp' => '2025-01-08T00:00:00Z' }
        ]
      end

      it 'groups into ISO week buckets' do
        timeline = reporter.format_timeline(activities, :week)
        expect(timeline.map { |e| e[:period] }).to include('2025-W01', '2025-W02')
      end
    end

    context 'grouping by month' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-02-14T10:00:00Z' },
          { 'action' => 'purchase', 'timestamp' => '2025-02-28T18:00:00Z' },
          { 'action' => 'logout', 'timestamp' => '2025-03-01T01:00:00Z' }
        ]
      end

      it 'groups into monthly buckets' do
        timeline = reporter.format_timeline(activities, :month)
        expect(timeline.map { |e| e[:period] }).to include('2025-02', '2025-03')
      end
    end

    context 'with invalid timestamp values' do
      let(:fixed_now) do
        Time.utc(2025, 1, 10, 12, 0, 0)
      end

      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => 'not-a-time' }
        ]
      end

      it 'falls back to current time to determine period' do
        allow(Time).to receive(:now).and_return(fixed_now)
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline[0][:period]).to eq('2025-01-10')
      end
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 'u1',
        summary: { total_actions: 2 },
        action_breakdown: { 'login' => 2 },
        patterns: [],
        anomalies: [],
        timeline: [],
        insights: []
      }
    end

    context 'when filepath is not provided' do
      it 'returns the JSON data' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be true
        expect(result[:data]).to be_a(String)
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq('u1')
      end
    end

    context 'when filepath is provided' do
      it 'writes the JSON to the file and returns metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be true
          expect(result[:filepath]).to eq(path)
          expect(File.exist?(path)).to be true
          content = File.read(path)
          expect(JSON.parse(content)['user_id']).to eq('u1')
          expect(result[:size]).to eq(content.bytesize)
        end
      end
    end

    context 'when writing fails' do
      it 'returns an error hash' do
        allow(JSON).to receive(:pretty_generate).and_raise(StandardError.new('boom'))
        result = reporter.export_to_json(report, '/tmp/whatever.json')
        expect(result[:success]).to be false
        expect(result[:error]).to eq('boom')
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than two users' do
      it 'returns an error report' do
        result = reporter.compare_users(['u1'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
      end
    end

    context 'with two or more users' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{ 'action' => 'login',
                                                                                    'timestamp' => '2025-01-01T00:00:00Z' }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{ 'action' => 'purchase',
                                                                                    'timestamp' => '2025-01-01T01:00:00Z' }])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return(
          { total_actions: 1, unique_actions: 1, action_counts: { 'login' => 1 },
            first_activity: '2025-01-01T00:00:00Z', last_activity: '2025-01-01T00:00:00Z', most_frequent: 'login' }
        )
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return(
          { total_actions: 1, unique_actions: 1, action_counts: { 'purchase' => 1 },
            first_activity: '2025-01-01T01:00:00Z', last_activity: '2025-01-01T01:00:00Z', most_frequent: 'purchase' }
        )
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return(
          { total_actions: 0, unique_actions: 0, action_counts: {}, first_activity: '2025-01-01T00:00:00Z',
            last_activity: '2025-01-01T00:00:00Z', most_frequent: 'unknown' }
        )

        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'login',
                                                              'timestamp' => '2025-01-01T00:00:00Z' }]).and_return(70.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'purchase',
                                                              'timestamp' => '2025-01-01T01:00:00Z' }]).and_return(85.5)
        allow(reporter).to receive(:fetch_user_score).with([]).and_return(0.0)
      end

      it 'returns a sorted comparison with top user and average score' do
        result = reporter.compare_users(%w[u1 u2 u3])
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[u2 u1 u3])
        expect(result[:comparisons].find { |c| c[:user_id] == 'u2' }[:most_frequent_action]).to eq('purchase')
        expect(result[:top_user]).to eq('u2')
        expect(result[:average_score]).to eq(((85.5 + 70.0 + 0.0) / 3.0).round(2))
      end
    end
  end
end
