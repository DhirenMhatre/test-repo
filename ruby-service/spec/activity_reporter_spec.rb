require 'spec_helper'
require 'json'
require 'time'
require 'tmpdir'
require 'rails_helper'

RSpec.describe ActivityReporter do
  describe '#initialize' do
    context 'with default URLs' do
      it 'sets default service URLs' do
        reporter = described_class.new
        expect(reporter.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
        expect(reporter.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
      end
    end

    context 'with custom URLs' do
      it 'sets provided service URLs' do
        reporter = described_class.new(go_service_url: 'http://go.example', python_service_url: 'http://py.example')
        expect(reporter.instance_variable_get(:@go_service_url)).to eq('http://go.example')
        expect(reporter.instance_variable_get(:@python_service_url)).to eq('http://py.example')
      end
    end
  end

  describe '#generate_report' do
    let(:reporter) { described_class.new }
    let(:user_id) { 'user-123' }
    let(:now_time) { Time.utc(2025, 1, 3, 0, 0, 0) }
    let(:activities) do
      [
        { 'action' => 'login', 'timestamp' => '2025-01-01T10:00:00Z' },
        { 'action' => 'view', 'timestamp' => '2025-01-01T12:00:00Z' },
        { 'action' => 'purchase', 'timestamp' => '2025-01-02T09:00:00Z' }
      ]
    end
    let(:stats) do
      {
        total_actions: 3,
        unique_actions: 3,
        action_counts: { 'login' => 1, 'view' => 1, 'purchase' => 1 },
        first_activity: '2025-01-01T10:00:00Z',
        last_activity: '2025-01-02T09:00:00Z',
        most_frequent: 'login'
      }
    end
    let(:patterns_raw) do
      [
        { 'pattern_type' => 'streak', 'description' => 'daily logins', 'confidence' => 0.8 },
        { 'pattern_type' => 'burst', 'description' => 'afternoon spikes', 'confidence' => 0.6 },
        { 'pattern_type' => 'routine', 'description' => 'weekday usage', 'confidence' => 0.7 }
      ]
    end
    let(:score) { 76.0 }
    let(:anomalies) do
      [
        { 'timestamp' => '2025-01-01T02:00:00Z', 'reason' => 'suspicious location' },
        { 'timestamp' => '2025-01-02T22:00:00Z', 'reason' => 'unusual volume' }
      ]
    end

    before do
      allow(Time).to receive(:now).and_return(now_time)
      allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
      allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
      allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
      allow(reporter).to receive(:fetch_user_score).with(activities).and_return(score)
      allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
    end

    it 'builds a comprehensive report with summary, patterns, anomalies, timeline, and insights' do
      report = reporter.generate_report(user_id, { group_by: :day })

      expect(report[:user_id]).to eq(user_id)
      expect(report[:generated_at]).to eq(now_time.iso8601)
      expect(report[:summary]).to include(
        total_actions: 3,
        unique_actions: 3,
        engagement_score: 76.0,
        first_activity: '2025-01-01T10:00:00Z',
        last_activity: '2025-01-02T09:00:00Z'
      )
      expect(report[:action_breakdown]).to eq({ 'login' => 1, 'view' => 1, 'purchase' => 1 })

      expect(report[:patterns]).to contain_exactly(
        { type: 'streak', description: 'daily logins', confidence: 0.8 },
        { type: 'burst', description: 'afternoon spikes', confidence: 0.6 },
        { type: 'routine', description: 'weekday usage', confidence: 0.7 }
      )

      expect(report[:anomalies]).to eq(anomalies)

      expect(report[:timeline]).to eq([
                                        {
                                          period: '2025-01-01',
                                          total_actions: 2,
                                          actions: { 'login' => 1, 'view' => 1 },
                                          first_timestamp: '2025-01-01T10:00:00Z',
                                          last_timestamp: '2025-01-01T12:00:00Z'
                                        },
                                        {
                                          period: '2025-01-02',
                                          total_actions: 1,
                                          actions: { 'purchase' => 1 },
                                          first_timestamp: '2025-01-02T09:00:00Z',
                                          last_timestamp: '2025-01-02T09:00:00Z'
                                        }
                                      ])

      expect(report[:insights]).to include('Highly engaged user with strong activity patterns')
      expect(report[:insights]).to include('Clear behavioral patterns detected')
      expect(report[:insights]).to include('2 anomalous activities detected - review recommended')
      expect(report[:insights]).not_to include('Power user - high volume of activities')
      expect(report[:insights]).not_to include('Diverse activity profile across multiple action types')
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report' do
        report = reporter.generate_report(user_id)
        expect(report[:error]).to be true
        expect(report[:message]).to eq('No activities found')
        expect(report[:generated_at]).to eq(now_time.iso8601)
      end
    end

    context 'when thresholds trigger additional insights' do
      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 11,
          action_counts: { 'a' => 100, 'b' => 50 },
          first_activity: '2025-01-01T00:00:00Z',
          last_activity: '2025-01-02T00:00:00Z',
          most_frequent: 'a'
        }
      end
      let(:score) { 55.0 }
      let(:patterns_raw) { [{ 'pattern_type' => 'x', 'description' => 'y', 'confidence' => 0.3 }] }
      let(:anomalies) { [] }

      it 'includes power user and diverse activity insights and moderate engagement' do
        report = reporter.generate_report(user_id)
        expect(report[:insights]).to include('Power user - high volume of activities')
        expect(report[:insights]).to include('Diverse activity profile across multiple action types')
        expect(report[:insights]).to include('Moderately engaged user with regular activity')
      end
    end

    context 'when user has low score and anomalies only' do
      let(:stats) do
        {
          total_actions: 1,
          unique_actions: 1,
          action_counts: { 'a' => 1 },
          first_activity: '2025-01-01T00:00:00Z',
          last_activity: '2025-01-01T00:00:00Z',
          most_frequent: 'a'
        }
      end
      let(:score) { 10.0 }
      let(:patterns_raw) { [] }
      let(:anomalies) { [{ 'timestamp' => '2025-01-01T01:00:00Z', 'reason' => 'x' }] }

      it 'includes low engagement and anomaly insights' do
        report = reporter.generate_report(user_id)
        expect(report[:insights]).to include('Low engagement - consider re-engagement strategies')
        expect(report[:insights]).to include('1 anomalous activities detected - review recommended')
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) { described_class.new }

    context 'with empty activities' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([])).to eq([])
      end
    end

    context 'when grouping by day' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T08:00:00Z' },
          { 'action' => 'login', 'timestamp' => '2025-01-01T09:00:00Z' },
          { 'action' => 'view', 'timestamp' => '2025-01-02T10:00:00Z' }
        ]
      end

      it 'groups activities per day with proper counts and timestamps' do
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline).to eq([
                                 {
                                   period: '2025-01-01',
                                   total_actions: 2,
                                   actions: { 'login' => 2 },
                                   first_timestamp: '2025-01-01T08:00:00Z',
                                   last_timestamp: '2025-01-01T09:00:00Z'
                                 },
                                 {
                                   period: '2025-01-02',
                                   total_actions: 1,
                                   actions: { 'view' => 1 },
                                   first_timestamp: '2025-01-02T10:00:00Z',
                                   last_timestamp: '2025-01-02T10:00:00Z'
                                 }
                               ])
      end
    end

    context 'when grouping by hour' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T08:15:00Z' },
          { 'action' => 'view', 'timestamp' => '2025-01-01T08:45:00Z' },
          { 'action' => 'purchase', 'timestamp' => '2025-01-01T09:05:00Z' }
        ]
      end

      it 'groups activities per hour with HH:00 periods' do
        timeline = reporter.format_timeline(activities, :hour)
        expect(timeline).to eq([
                                 {
                                   period: '2025-01-01 08:00',
                                   total_actions: 2,
                                   actions: { 'login' => 1, 'view' => 1 },
                                   first_timestamp: '2025-01-01T08:15:00Z',
                                   last_timestamp: '2025-01-01T08:45:00Z'
                                 },
                                 {
                                   period: '2025-01-01 09:00',
                                   total_actions: 1,
                                   actions: { 'purchase' => 1 },
                                   first_timestamp: '2025-01-01T09:05:00Z',
                                   last_timestamp: '2025-01-01T09:05:00Z'
                                 }
                               ])
      end
    end

    context 'when grouping by week' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T12:00:00Z' },
          { 'action' => 'view', 'timestamp' => '2025-01-10T09:00:00Z' }
        ]
      end

      it 'groups activities per ISO week' do
        timeline = reporter.format_timeline(activities, :week)
        expect(timeline).to eq([
                                 {
                                   period: '2025-W01',
                                   total_actions: 1,
                                   actions: { 'login' => 1 },
                                   first_timestamp: '2025-01-01T12:00:00Z',
                                   last_timestamp: '2025-01-01T12:00:00Z'
                                 },
                                 {
                                   period: '2025-W02',
                                   total_actions: 1,
                                   actions: { 'view' => 1 },
                                   first_timestamp: '2025-01-10T09:00:00Z',
                                   last_timestamp: '2025-01-10T09:00:00Z'
                                 }
                               ])
      end
    end

    context 'when grouping by month' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-31T12:00:00Z' },
          { 'action' => 'view', 'timestamp' => '2025-02-01T09:00:00Z' }
        ]
      end

      it 'groups activities per month' do
        timeline = reporter.format_timeline(activities, :month)
        expect(timeline).to eq([
                                 {
                                   period: '2025-01',
                                   total_actions: 1,
                                   actions: { 'login' => 1 },
                                   first_timestamp: '2025-01-31T12:00:00Z',
                                   last_timestamp: '2025-01-31T12:00:00Z'
                                 },
                                 {
                                   period: '2025-02',
                                   total_actions: 1,
                                   actions: { 'view' => 1 },
                                   first_timestamp: '2025-02-01T09:00:00Z',
                                   last_timestamp: '2025-02-01T09:00:00Z'
                                 }
                               ])
      end
    end

    context 'with unknown group_by value' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-03-01T00:00:00Z' },
          { 'action' => 'view', 'timestamp' => '2025-03-01T01:00:00Z' }
        ]
      end

      it 'defaults to day grouping' do
        timeline = reporter.format_timeline(activities, :unknown)
        expect(timeline.length).to eq(1)
        expect(timeline.first[:period]).to eq('2025-03-01')
        expect(timeline.first[:total_actions]).to eq(2)
      end
    end

    context 'with invalid timestamps' do
      let(:now_time) { Time.utc(2025, 2, 10, 15, 30, 0) }
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => 'not-a-time' },
          { 'action' => 'view', 'timestamp' => 'still-bad' }
        ]
      end

      before do
        allow(Time).to receive(:now).and_return(now_time)
      end

      it 'uses current time for grouping and preserves original timestamps in output' do
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.length).to eq(1)
        expect(timeline.first[:period]).to eq('2025-02-10')
        expect(timeline.first[:first_timestamp]).to eq('not-a-time')
        expect(timeline.first[:last_timestamp]).to eq('still-bad')
        expect(timeline.first[:actions]).to eq({ 'login' => 1, 'view' => 1 })
      end
    end
  end

  describe '#export_to_json' do
    let(:reporter) { described_class.new }
    let(:report) do
      {
        user_id: 1,
        generated_at: '2025-01-01T00:00:00Z',
        summary: { total_actions: 2 },
        action_breakdown: { 'login' => 1, 'view' => 1 },
        patterns: [],
        anomalies: [],
        timeline: [],
        insights: []
      }
    end

    context 'when no filepath is provided' do
      it 'returns success with JSON data' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be true
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq(1)
        expect(parsed['summary']['total_actions']).to eq(2)
      end
    end

    context 'when filepath is provided' do
      it 'writes the file and returns success with metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be true
          expect(result[:filepath]).to eq(path)
          expect(result[:size]).to be > 0
          expect(File.exist?(path)).to be true
          content = File.read(path)
          expect(JSON.parse(content)['user_id']).to eq(1)
        end
      end
    end

    context 'when writing fails' do
      it 'returns a failure with error message' do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be false
          expect(result[:error]).to eq('disk full')
        end
      end
    end
  end

  describe '#compare_users' do
    let(:reporter) { described_class.new }

    context 'when fewer than two users provided' do
      it 'returns an error report' do
        result = reporter.compare_users([1])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with multiple users' do
      let(:user_ids) { [1, 2, 3] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(1).and_return([{ 'action' => 'a' }])
        allow(reporter).to receive(:fetch_user_activities).with(2).and_return([{ 'action' => 'b' }])
        allow(reporter).to receive(:fetch_user_activities).with(3).and_return([{ 'action' => 'c' }])

        allow(reporter).to receive(:fetch_activity_stats).with(1).and_return(
          { total_actions: 10, unique_actions: 3, action_counts: {}, first_activity: '', last_activity: '',
            most_frequent: 'login' }
        )
        allow(reporter).to receive(:fetch_activity_stats).with(2).and_return(
          { total_actions: 5, unique_actions: 2, action_counts: {}, first_activity: '', last_activity: '',
            most_frequent: 'view' }
        )
        allow(reporter).to receive(:fetch_activity_stats).with(3).and_return(
          { total_actions: 20, unique_actions: 4, action_counts: {}, first_activity: '', last_activity: '',
            most_frequent: 'purchase' }
        )

        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'a' }]).and_return(50.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'b' }]).and_return(75.5)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'c' }]).and_return(60.2)
      end

      it 'sorts users by engagement score descending and computes average' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq([2, 3, 1])
        expect(result[:comparisons].first[:most_frequent_action]).to eq('view')
        expect(result[:top_user]).to eq(2)
        expect(result[:average_score]).to eq(61.9)
      end
    end
  end
end
