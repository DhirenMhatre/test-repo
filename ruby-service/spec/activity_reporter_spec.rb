require 'spec_helper'
require 'json'
require 'tmpdir'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) { described_class.new }
  let(:fixed_time) { Time.utc(2023, 5, 1, 12, 0, 0) }

  before do
    allow(Time).to receive(:now).and_return(fixed_time)
  end

  describe '#generate_report' do
    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(42).and_return([])
      end

      it 'returns an error report with message and timestamp' do
        result = reporter.generate_report(42)
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'when activities exist' do
      let(:user_id) { 101 }
      let(:activities) do
        [
          { 'timestamp' => '2023-04-29T10:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2023-04-29T12:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-04-30T09:30:00Z', 'action' => 'logout' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 2,
          action_counts: { 'login' => 1, 'click' => 1, 'logout' => 1 },
          first_activity: '2023-04-29T10:00:00Z',
          last_activity: '2023-04-30T09:30:00Z',
          most_frequent: 'click'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'burst', 'description' => 'Quick succession actions', 'confidence' => 0.92 }
        ]
      end

      let(:user_score) { 88.5 }
      let(:anomalies) { [{ id: 'anom-1' }, { id: 'anom-2' }] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a comprehensive report with summary, patterns, anomalies, timeline, and insights' do
        result = reporter.generate_report(user_id)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(fixed_time.iso8601)

        expect(result[:summary][:total_actions]).to eq(3)
        expect(result[:summary][:unique_actions]).to eq(2)
        expect(result[:summary][:engagement_score]).to eq(user_score)
        expect(result[:summary][:first_activity]).to eq('2023-04-29T10:00:00Z')
        expect(result[:summary][:last_activity]).to eq('2023-04-30T09:30:00Z')

        expect(result[:action_breakdown]).to eq({ 'login' => 1, 'click' => 1, 'logout' => 1 })

        expect(result[:patterns]).to be_an(Array)
        expect(result[:patterns].first[:type]).to eq('burst')
        expect(result[:patterns].first[:description]).to eq('Quick succession actions')
        expect(result[:patterns].first[:confidence]).to eq(0.92)

        expect(result[:anomalies]).to eq(anomalies)

        expect(result[:timeline]).to be_an(Array)
        periods = result[:timeline].map { |e| e[:period] }
        expect(periods).to eq(%w[2023-04-29 2023-04-30])

        insights = result[:insights]
        expect(insights).to include('Highly engaged user with strong activity patterns')
        expect(insights).to include('2 anomalous activities detected - review recommended')
        expect(insights.any? { |i| i.include?('Power user') }).to eq(false)
        expect(insights.any? { |i| i.include?('Diverse activity profile') }).to eq(false)
        expect(insights.any? { |i| i.include?('Clear behavioral patterns') }).to eq(false)
      end

      it 'respects group_by option when generating timeline by hour' do
        result = reporter.generate_report(user_id, { group_by: :hour })
        expect(result[:timeline].map do |e|
          e[:period]
        end).to eq(['2023-04-29 10:00', '2023-04-29 12:00', '2023-04-30 09:00'])
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities array is empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([])).to eq([])
      end
    end

    context 'when grouping by day' do
      let(:activities) do
        [
          { 'timestamp' => '2023-04-29T01:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2023-04-29T15:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-04-30T10:00:00Z', 'action' => 'logout' }
        ]
      end

      it 'groups activities per day with counts and orders periods ascending' do
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.size).to eq(2)

        first = timeline[0]
        second = timeline[1]

        expect(first[:period]).to eq('2023-04-29')
        expect(first[:total_actions]).to eq(2)
        expect(first[:actions]).to eq({ 'login' => 1, 'click' => 1 })
        expect(first[:first_timestamp]).to eq('2023-04-29T01:00:00Z')
        expect(first[:last_timestamp]).to eq('2023-04-29T15:00:00Z')

        expect(second[:period]).to eq('2023-04-30')
        expect(second[:total_actions]).to eq(1)
        expect(second[:actions]).to eq({ 'logout' => 1 })
        expect(second[:first_timestamp]).to eq('2023-04-30T10:00:00Z')
        expect(second[:last_timestamp]).to eq('2023-04-30T10:00:00Z')
      end
    end

    context 'when grouping by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2023-04-29T09:05:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-04-29T09:55:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-04-29T10:00:10Z', 'action' => 'view' }
        ]
      end

      it 'groups activities per hour with proper bucket labels' do
        timeline = reporter.format_timeline(activities, :hour)
        expect(timeline.map { |e| e[:period] }).to eq(['2023-04-29 09:00', '2023-04-29 10:00'])
        expect(timeline[0][:actions]).to eq({ 'view' => 1, 'click' => 1 })
        expect(timeline[1][:actions]).to eq({ 'view' => 1 })
      end
    end

    context 'when grouping by week' do
      let(:activities) do
        [
          { 'timestamp' => '2023-01-02T10:00:00Z', 'action' => 'a' }, # ISO week 1 (Mon)
          { 'timestamp' => '2023-01-08T10:00:00Z', 'action' => 'b' }  # ISO week 1 (Sun)
        ]
      end

      it 'groups by ISO week' do
        timeline = reporter.format_timeline(activities, :week)
        expect(timeline.size).to eq(1)
        expect(timeline.first[:period]).to eq('2023-W01')
        expect(timeline.first[:total_actions]).to eq(2)
      end
    end

    context 'when grouping by month' do
      let(:activities) do
        [
          { 'timestamp' => '2023-03-01T00:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2023-03-31T23:59:59Z', 'action' => 'b' }
        ]
      end

      it 'groups by month correctly' do
        timeline = reporter.format_timeline(activities, :month)
        expect(timeline.size).to eq(1)
        expect(timeline.first[:period]).to eq('2023-03')
        expect(timeline.first[:actions]).to eq({ 'a' => 1, 'b' => 1 })
      end
    end

    context 'when group_by is unknown' do
      let(:activities) do
        [
          { 'timestamp' => '2023-04-01T00:00:00Z', 'action' => 'x' },
          { 'timestamp' => '2023-04-02T00:00:00Z', 'action' => 'y' }
        ]
      end

      it 'defaults to day grouping' do
        timeline = reporter.format_timeline(activities, :unknown_group)
        expect(timeline.map { |e| e[:period] }).to eq(%w[2023-04-01 2023-04-02])
      end
    end

    context 'when an activity has an invalid timestamp' do
      let(:activities) do
        [
          { 'timestamp' => 'not-a-time', 'action' => 'invalid_action' }
        ]
      end

      it 'falls back to current day for grouping and does not raise errors' do
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.size).to eq(1)
        expect(timeline.first[:period]).to eq(fixed_time.strftime('%Y-%m-%d'))
        expect(timeline.first[:actions]).to eq({ 'invalid_action' => 1 })
      end
    end
  end

  describe '#export_to_json' do
    let(:report_hash) do
      {
        user_id: 123,
        summary: { total_actions: 2 },
        timeline: [],
        generated_at: fixed_time.iso8601
      }
    end

    context 'when no filepath is provided' do
      it 'returns a success hash with JSON data' do
        result = reporter.export_to_json(report_hash)
        expect(result[:success]).to eq(true)
        expect(result[:data]).to be_a(String)

        expected_json = JSON.pretty_generate(report_hash)
        expect(result[:data]).to eq(expected_json)
      end
    end

    context 'when a filepath is provided' do
      it 'writes the JSON to the file and returns metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          expected_json = JSON.pretty_generate(report_hash)
          result = reporter.export_to_json(report_hash, path)

          expect(result[:success]).to eq(true)
          expect(result[:filepath]).to eq(path)
          expect(result[:size]).to eq(expected_json.bytesize)

          content = File.read(path)
          expect(content).to eq(expected_json)
        end
      end
    end

    context 'when writing to a file raises an error' do
      it 'returns a failure hash with the error message' do
        allow(File).to receive(:write).and_raise(StandardError.new('boom'))
        result = reporter.export_to_json(report_hash, '/tmp/will-fail.json')
        expect(result[:success]).to eq(false)
        expect(result[:error]).to eq('boom')
      end
    end
  end

  describe '#compare_users' do
    context 'when less than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users([1])
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'when comparing multiple users' do
      let(:user_ids) { [2, 1, 3] }

      before do
        allow(reporter).to receive(:fetch_user_activities) do |uid|
          [{ 'user' => uid }]
        end

        allow(reporter).to receive(:fetch_activity_stats) do |uid|
          {
            total_actions: { 1 => 10, 2 => 50, 3 => 5 }[uid],
            unique_actions: 0,
            action_counts: {},
            first_activity: fixed_time.iso8601,
            last_activity: fixed_time.iso8601,
            most_frequent: { 1 => 'login', 2 => 'click', 3 => 'view' }[uid]
          }
        end

        allow(reporter).to receive(:fetch_user_score) do |activities|
          uid = activities.first['user']
          { 1 => 70.0, 2 => 95.0, 3 => 70.0 }[uid]
        end
      end

      it 'returns comparisons sorted by engagement score descending with top user and average score' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)

        comparisons = result[:comparisons]
        expect(comparisons.map { |c| c[:user_id] }).to eq([2, 1, 3])

        top_user = result[:top_user]
        expect(top_user).to eq(2)

        avg = result[:average_score]
        expect(avg).to eq(((95.0 + 70.0 + 70.0) / 3.0).round(2))

        comp_2 = comparisons.find { |c| c[:user_id] == 2 }
        expect(comp_2[:total_actions]).to eq(50)
        expect(comp_2[:engagement_score]).to eq(95.0)
        expect(comp_2[:most_frequent_action]).to eq('click')
      end
    end
  end
end
