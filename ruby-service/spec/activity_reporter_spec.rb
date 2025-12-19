require 'spec_helper'
require 'tmpdir'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new
  end

  describe '#generate_report' do
    let(:user_id) do
      123
    end

    context 'when no activities exist for the user' do
      let(:fixed_time) do
        Time.utc(2023, 1, 1, 12, 0, 0)
      end

      before do
        allow(Time).to receive(:now).and_return(fixed_time)
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report with a helpful message' do
        result = reporter.generate_report(user_id)
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with activities and complete dependent data' do
      let(:fixed_time) do
        Time.utc(2023, 5, 3, 0, 0, 0)
      end

      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2023-05-01T10:15:00Z' },
          { 'action' => 'view', 'timestamp' => '2023-05-01T11:00:00Z' },
          { 'action' => 'purchase', 'timestamp' => '2023-05-02T09:30:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 120,
          unique_actions: 11,
          action_counts: { 'login' => 1, 'view' => 1, 'purchase' => 1 },
          first_activity: '2023-05-01T10:15:00Z',
          last_activity: '2023-05-02T09:30:00Z',
          most_frequent: 'purchase'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'morning_activity', 'description' => 'High morning usage', 'confidence' => 0.92 },
          { 'pattern_type' => 'weekday_focus', 'description' => 'Mostly weekdays', 'confidence' => 0.88 },
          { 'pattern_type' => 'purchase_cluster', 'description' => 'Purchases cluster on Tuesdays',
            'confidence' => 0.73 }
        ]
      end

      let(:user_score) do
        88.0
      end

      let(:anomalies) do
        [
          { 'action' => 'delete', 'timestamp' => '2023-05-02T20:00:00Z' },
          { 'action' => 'login', 'timestamp' => '2023-05-02T23:59:59Z', 'note' => 'suspicious location' }
        ]
      end

      before do
        allow(Time).to receive(:now).and_return(fixed_time)
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a complete report with summary, timeline, patterns, anomalies, and insights' do
        result = reporter.generate_report(user_id)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(fixed_time.iso8601)

        expect(result[:summary][:total_actions]).to eq(120)
        expect(result[:summary][:unique_actions]).to eq(11)
        expect(result[:summary][:engagement_score]).to eq(user_score)
        expect(result[:summary][:first_activity]).to eq('2023-05-01T10:15:00Z')
        expect(result[:summary][:last_activity]).to eq('2023-05-02T09:30:00Z')

        expect(result[:action_breakdown]).to eq({ 'login' => 1, 'view' => 1, 'purchase' => 1 })

        expected_patterns = patterns.map do |p|
          {
            type: p['pattern_type'],
            description: p['description'],
            confidence: p['confidence']
          }
        end
        expect(result[:patterns]).to eq(expected_patterns)

        expect(result[:anomalies]).to eq(anomalies)

        expected_timeline = [
          {
            period: '2023-05-01',
            total_actions: 2,
            actions: { 'login' => 1, 'view' => 1 },
            first_timestamp: '2023-05-01T10:15:00Z',
            last_timestamp: '2023-05-01T11:00:00Z'
          },
          {
            period: '2023-05-02',
            total_actions: 1,
            actions: { 'purchase' => 1 },
            first_timestamp: '2023-05-02T09:30:00Z',
            last_timestamp: '2023-05-02T09:30:00Z'
          }
        ]
        expect(result[:timeline]).to eq(expected_timeline)

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('2 anomalous activities detected - review recommended')
        expect(result[:insights]).to include('Power user - high volume of activities')
      end

      it 'honors the group_by option in timeline' do
        result = reporter.generate_report(user_id, group_by: :hour)
        periods = result[:timeline].map do |e|
          e[:period]
        end
        expect(periods).to eq(['2023-05-01 10:00', '2023-05-01 11:00', '2023-05-02 09:00'])
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities array is empty' do
      it 'returns an empty array' do
        result = reporter.format_timeline([])
        expect(result).to eq([])
      end
    end

    context 'groups by day (default)' do
      let(:activities) do
        [
          { 'action' => 'a', 'timestamp' => '2023-06-01T00:00:01Z' },
          { 'action' => 'b', 'timestamp' => '2023-06-01T12:34:56Z' },
          { 'action' => 'a', 'timestamp' => '2023-06-02T01:02:03Z' }
        ]
      end

      it 'aggregates counts and sorts by day period' do
        result = reporter.format_timeline(activities)
        expect(result.map { |r| r[:period] }).to eq(%w[2023-06-01 2023-06-02])
        expect(result[0][:total_actions]).to eq(2)
        expect(result[0][:actions]).to eq({ 'a' => 1, 'b' => 1 })
        expect(result[1][:total_actions]).to eq(1)
        expect(result[1][:actions]).to eq({ 'a' => 1 })
      end
    end

    context 'groups by week' do
      let(:activities) do
        [
          { 'action' => 'x', 'timestamp' => '2023-05-01T10:00:00Z' },
          { 'action' => 'y', 'timestamp' => '2023-05-07T23:59:59Z' },
          { 'action' => 'z', 'timestamp' => '2023-05-08T00:00:00Z' }
        ]
      end

      it 'uses ISO week format and sorts correctly' do
        result = reporter.format_timeline(activities, :week)
        expect(result.map { |r| r[:period] }).to eq(%w[2023-W18 2023-W19])
        expect(result[0][:total_actions]).to eq(2)
        expect(result[1][:total_actions]).to eq(1)
      end
    end

    context 'groups by month' do
      let(:activities) do
        [
          { 'action' => 'm', 'timestamp' => '2023-05-31T23:59:59Z' },
          { 'action' => 'n', 'timestamp' => '2023-06-01T00:00:00Z' }
        ]
      end

      it 'uses month granularity' do
        result = reporter.format_timeline(activities, :month)
        expect(result.map { |r| r[:period] }).to eq(%w[2023-05 2023-06])
        expect(result[0][:actions]).to eq({ 'm' => 1 })
        expect(result[1][:actions]).to eq({ 'n' => 1 })
      end
    end

    context 'groups by hour' do
      let(:activities) do
        [
          { 'action' => 'a', 'timestamp' => '2023-06-01T10:15:00Z' },
          { 'action' => 'b', 'timestamp' => '2023-06-01T10:59:59Z' },
          { 'action' => 'a', 'timestamp' => '2023-06-01T11:00:00Z' }
        ]
      end

      it 'uses hour granularity' do
        result = reporter.format_timeline(activities, :hour)
        expect(result.map { |r| r[:period] }).to eq(['2023-06-01 10:00', '2023-06-01 11:00'])
        expect(result[0][:total_actions]).to eq(2)
        expect(result[1][:total_actions]).to eq(1)
      end
    end

    context 'falls back to day when group_by is unknown' do
      let(:activities) do
        [
          { 'action' => 'a', 'timestamp' => '2023-06-01T10:00:00Z' },
          { 'action' => 'b', 'timestamp' => '2023-06-01T11:00:00Z' }
        ]
      end

      it 'uses day grouping by default' do
        result = reporter.format_timeline(activities, :unknown)
        expect(result.map { |r| r[:period] }).to eq(['2023-06-01'])
        expect(result[0][:total_actions]).to eq(2)
      end
    end

    context 'handles invalid timestamp strings by using current time for grouping' do
      let(:fixed_time) do
        Time.utc(2023, 1, 1, 0, 0, 0)
      end

      let(:activities) do
        [
          { 'action' => 'a', 'timestamp' => 'invalid-timestamp' }
        ]
      end

      before do
        allow(Time).to receive(:now).and_return(fixed_time)
      end

      it 'groups into the current day and preserves raw timestamps in first/last' do
        result = reporter.format_timeline(activities)
        expect(result.length).to eq(1)
        expect(result[0][:period]).to eq('2023-01-01')
        expect(result[0][:first_timestamp]).to eq('invalid-timestamp')
        expect(result[0][:last_timestamp]).to eq('invalid-timestamp')
      end
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 10,
        summary: { total_actions: 5 },
        timeline: [{ period: '2023-06-01', total_actions: 5 }]
      }
    end

    context 'when a filepath is provided' do
      it 'writes pretty JSON to the given file and returns metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be true
          expect(result[:filepath]).to eq(path)
          expected_json = JSON.pretty_generate(report)
          expect(result[:size]).to eq(expected_json.bytesize)
          content = File.read(path)
          expect(content).to eq(expected_json)
        end
      end

      it 'returns an error when writing fails' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be false
          expect(result[:error]).to eq('disk full')
        end
      end
    end

    context 'when no filepath is provided' do
      it 'returns the JSON string in the response' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be true
        expect(result[:data]).to be_a(String)
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq(10)
        expect(parsed['summary']['total_actions']).to eq(5)
      end
    end
  end

  describe '#compare_users' do
    context 'with fewer than 2 users' do
      it 'returns an error report' do
        result = reporter.compare_users([1])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
      end
    end

    context 'with multiple users' do
      let(:user_ids) do
        [1, 2, 3]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(1).and_return([{ 'a' => 1 }])
        allow(reporter).to receive(:fetch_user_activities).with(2).and_return([{ 'a' => 2 }, { 'b' => 3 }])
        allow(reporter).to receive(:fetch_user_activities).with(3).and_return([])

        allow(reporter).to receive(:fetch_activity_stats).with(1).and_return({ total_actions: 10, unique_actions: 3,
                                                                               action_counts: { 'a' => 5 }, first_activity: 't1', last_activity: 't2', most_frequent: 'a' })
        allow(reporter).to receive(:fetch_activity_stats).with(2).and_return({ total_actions: 20, unique_actions: 5,
                                                                               action_counts: { 'b' => 10 }, first_activity: 't3', last_activity: 't4', most_frequent: 'b' })
        allow(reporter).to receive(:fetch_activity_stats).with(3).and_return({ total_actions: 5, unique_actions: 2,
                                                                               action_counts: { 'c' => 5 }, first_activity: 't5', last_activity: 't6', most_frequent: 'c' })

        allow(reporter).to receive(:fetch_user_score).with([{ 'a' => 1 }]).and_return(50.5)
        allow(reporter).to receive(:fetch_user_score).with([{ 'a' => 2 }, { 'b' => 3 }]).and_return(75.3)
        allow(reporter).to receive(:fetch_user_score).with([]).and_return(40.0)
      end

      it 'returns comparisons sorted by engagement score descending' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq([2, 1, 3])
        expect(result[:comparisons][0][:engagement_score]).to eq(75.3)
        expect(result[:comparisons][1][:engagement_score]).to eq(50.5)
        expect(result[:comparisons][2][:engagement_score]).to eq(40.0)
      end

      it 'includes top_user and average_score rounded to 2 decimals' do
        result = reporter.compare_users(user_ids)
        expect(result[:top_user]).to eq(2)
        expect(result[:average_score]).to eq(((75.3 + 50.5 + 40.0) / 3.0).round(2))
      end

      it 'includes most frequent action from stats' do
        result = reporter.compare_users(user_ids)
        most_frequents = result[:comparisons].each_with_object({}) do |c, h|
          h[c[:user_id]] = c[:most_frequent_action]
        end
        expect(most_frequents[1]).to eq('a')
        expect(most_frequents[2]).to eq('b')
        expect(most_frequents[3]).to eq('c')
      end
    end
  end
end
