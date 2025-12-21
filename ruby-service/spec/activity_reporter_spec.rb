require 'spec_helper'
require 'json'
require 'time'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new
  end

  describe '#generate_report' do
    let(:user_id) do
      'user-123'
    end

    context 'when no activities are found' do
      let(:fixed_time) do
        Time.utc(2025, 1, 1, 12, 0, 0)
      end

      before do
        allow(Time).to receive(:now).and_return(fixed_time)
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report and does not query other services' do
        expect(reporter).not_to receive(:fetch_activity_stats)
        expect(reporter).not_to receive(:fetch_activity_patterns)
        expect(reporter).not_to receive(:fetch_user_score)
        expect(reporter).not_to receive(:fetch_anomalies)

        result = reporter.generate_report(user_id)

        expect(result[:error]).to be(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with activities and complete data' do
      let(:fixed_time) do
        Time.utc(2025, 1, 5, 10, 30, 0)
      end

      let(:activities) do
        [
          { 'timestamp' => '2025-01-01T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T11:20:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-02T09:00:00Z', 'action' => 'logout' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 3,
          action_counts: { 'login' => 1, 'click' => 1, 'logout' => 1 },
          first_activity: '2025-01-01T10:15:00Z',
          last_activity: '2025-01-02T09:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'streak', 'description' => 'Daily login', 'confidence' => 0.9 },
          { 'pattern_type' => 'session', 'description' => 'Long sessions', 'confidence' => 0.7 },
          { 'pattern_type' => 'conversion', 'description' => 'High conversion after email', 'confidence' => 0.8 }
        ]
      end

      let(:user_score) do
        80.5
      end

      let(:anomalies) do
        [{ id: 'a1', reason: 'suspicious login' }]
      end

      before do
        allow(Time).to receive(:now).and_return(fixed_time)
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'returns a fully populated report with correct summary, patterns, anomalies, timeline and insights' do
        report = reporter.generate_report(user_id, group_by: :day)

        expect(report[:user_id]).to eq(user_id)
        expect(report[:generated_at]).to eq(fixed_time.iso8601)

        expect(report[:summary][:total_actions]).to eq(3)
        expect(report[:summary][:unique_actions]).to eq(3)
        expect(report[:summary][:engagement_score]).to eq(80.5)
        expect(report[:summary][:first_activity]).to eq('2025-01-01T10:15:00Z')
        expect(report[:summary][:last_activity]).to eq('2025-01-02T09:00:00Z')

        expect(report[:action_breakdown]).to eq({ 'login' => 1, 'click' => 1, 'logout' => 1 })

        expect(report[:patterns]).to eq(
          [
            { type: 'streak', description: 'Daily login', confidence: 0.9 },
            { type: 'session', description: 'Long sessions', confidence: 0.7 },
            { type: 'conversion', description: 'High conversion after email', confidence: 0.8 }
          ]
        )

        expect(report[:anomalies]).to eq(anomalies)

        expect(report[:timeline].size).to eq(2)
        expect(report[:timeline].map { |e| e[:period] }).to eq(['2025-01-01', '2025-01-02'])
        day1 = report[:timeline].find { |e| e[:period] == '2025-01-01' }
        expect(day1[:total_actions]).to eq(2)
        expect(day1[:actions]).to eq({ 'login' => 1, 'click' => 1 })
        expect(day1[:first_timestamp]).to eq('2025-01-01T10:15:00Z')
        expect(day1[:last_timestamp]).to eq('2025-01-01T11:20:00Z')

        expect(report[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(report[:insights]).to include('Clear behavioral patterns detected')
        expect(report[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(report[:insights]).not_to include('Power user - high volume of activities')
      end

      it 'respects the group_by option for month' do
        report = reporter.generate_report(user_id, group_by: :month)
        expect(report[:timeline].size).to eq(1)
        expect(report[:timeline].first[:period]).to eq('2025-01')
        expect(report[:timeline].first[:total_actions]).to eq(3)
      end
    end

    context 'with power user and diverse activity insights' do
      let(:activities) do
        Array.new(120) do |i|
          { 'timestamp' => "2025-01-0#{(i % 9) + 1}T10:00:00Z", 'action' => "action_#{i % 15}" }
        end
      end

      let(:stats) do
        {
          total_actions: 120,
          unique_actions: 15,
          action_counts: Hash[(0...15).map { |x| ["action_#{x}", 8] }],
          first_activity: '2025-01-01T10:00:00Z',
          last_activity: '2025-01-09T10:00:00Z',
          most_frequent: 'action_0'
        }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).and_return([{ 'pattern_type' => 'p', 'description' => 'd', 'confidence' => 0.5 }])
        allow(reporter).to receive(:fetch_user_score).and_return(60.0)
        allow(reporter).to receive(:fetch_anomalies).and_return([])
      end

      it 'includes power user and diverse activity insights' do
        report = reporter.generate_report('any')
        expect(report[:insights]).to include('Power user - high volume of activities')
        expect(report[:insights]).to include('Diverse activity profile across multiple action types')
        expect(report[:insights]).to include('Moderately engaged user with regular activity')
      end
    end

    context 'when activities contain invalid timestamps' do
      let(:fixed_time) do
        Time.utc(2025, 1, 10, 0, 0, 0)
      end

      let(:activities) do
        [
          { 'timestamp' => 'not-a-time', 'action' => 'login' }
        ]
      end

      before do
        allow(Time).to receive(:now).and_return(fixed_time)
        allow(reporter).to receive(:fetch_user_activities).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).and_return(
          {
            total_actions: 1,
            unique_actions: 1,
            action_counts: { 'login' => 1 },
            first_activity: 'not-a-time',
            last_activity: 'not-a-time',
            most_frequent: 'login'
          }
        )
        allow(reporter).to receive(:fetch_activity_patterns).and_return([])
        allow(reporter).to receive(:fetch_user_score).and_return(10.0)
        allow(reporter).to receive(:fetch_anomalies).and_return([])
      end

      it 'falls back to current time for grouping' do
        report = reporter.generate_report('u', group_by: :day)
        expect(report[:timeline].size).to eq(1)
        expect(report[:timeline].first[:period]).to eq('2025-01-10')
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities are empty' do
      it 'returns an empty array' do
        result = reporter.format_timeline([])
        expect(result).to eq([])
      end
    end

    context 'when grouping by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2025-02-01T10:05:00Z', 'action' => 'a' },
          { 'timestamp' => '2025-02-01T10:30:00Z', 'action' => 'b' },
          { 'timestamp' => '2025-02-01T11:00:00Z', 'action' => 'a' }
        ]
      end

      it 'buckets activities by the hour' do
        result = reporter.format_timeline(activities, :hour)
        expect(result.size).to eq(2)
        expect(result.map { |e| e[:period] }).to eq(['2025-02-01 10:00', '2025-02-01 11:00'])
        hour10 = result.first
        expect(hour10[:total_actions]).to eq(2)
        expect(hour10[:actions]).to eq({ 'a' => 1, 'b' => 1 })
        expect(hour10[:first_timestamp]).to eq('2025-02-01T10:05:00Z')
        expect(hour10[:last_timestamp]).to eq('2025-02-01T10:30:00Z')
      end
    end

    context 'when grouping by day' do
      let(:activities) do
        [
          { 'timestamp' => '2025-02-01T23:59:59Z', 'action' => 'x' },
          { 'timestamp' => '2025-02-02T00:00:01Z', 'action' => 'x' }
        ]
      end

      it 'buckets activities by the day' do
        result = reporter.format_timeline(activities, :day)
        expect(result.size).to eq(2)
        expect(result.map { |e| e[:period] }).to eq(['2025-02-01', '2025-02-02'])
      end
    end

    context 'when grouping by week' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-01T10:00:00Z', 'action' => 'w' },
          { 'timestamp' => '2025-01-08T10:00:00Z', 'action' => 'w' }
        ]
      end

      it 'buckets activities by ISO week' do
        result = reporter.format_timeline(activities, :week)
        expect(result.size).to eq(2)
        expect(result.all? { |e| e[:period].include?('-W') }).to be(true)
      end
    end

    context 'when grouping by month' do
      let(:activities) do
        [
          { 'timestamp' => '2025-03-01T00:00:00Z', 'action' => 'm' },
          { 'timestamp' => '2025-03-31T23:59:59Z', 'action' => 'm' },
          { 'timestamp' => '2025-04-01T00:00:00Z', 'action' => 'm' }
        ]
      end

      it 'buckets activities by the month' do
        result = reporter.format_timeline(activities, :month)
        expect(result.map { |e| e[:period] }).to eq(['2025-03', '2025-04'])
        month_mar = result.first
        expect(month_mar[:total_actions]).to eq(2)
        expect(month_mar[:actions]).to eq({ 'm' => 2 })
      end
    end

    context 'when grouping by unknown symbol' do
      let(:activities) do
        [
          { 'timestamp' => '2025-05-10T12:00:00Z', 'action' => 'u' }
        ]
      end

      it 'defaults to day grouping' do
        result = reporter.format_timeline(activities, :unknown)
        expect(result.size).to eq(1)
        expect(result.first[:period]).to eq('2025-05-10')
      end
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 'u1',
        generated_at: '2025-01-01T00:00:00Z',
        summary: { total_actions: 1 }
      }
    end

    context 'when no filepath is provided' do
      it 'returns the JSON data in the response' do
        result = reporter.export_to_json(report)
        expected = JSON.pretty_generate(report)
        expect(result[:success]).to be(true)
        expect(result[:data]).to eq(expected)
        expect(result[:filepath]).to be_nil
      end
    end

    context 'when a filepath is provided' do
      it 'writes the JSON to the file and returns metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expected = JSON.pretty_generate(report)
          expect(result[:success]).to be(true)
          expect(result[:filepath]).to eq(path)
          expect(result[:size]).to eq(expected.bytesize)
          expect(File.exist?(path)).to be(true)
          expect(File.read(path)).to eq(expected)
        end
      end
    end

    context 'when file write fails' do
      it 'returns an error payload' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          expect(File).to receive(:write).and_raise(StandardError.new('disk full'))
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be(false)
          expect(result[:error]).to eq('disk full')
        end
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than two users are provided' do
      let(:fixed_time) do
        Time.utc(2025, 1, 2, 0, 0, 0)
      end

      before do
        allow(Time).to receive(:now).and_return(fixed_time)
      end

      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to be(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with valid users' do
      let(:user_ids) do
        ['a', 'b', 'c']
      end

      let(:acts_a) do
        [{ 'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'view' }, { 'timestamp' => '2025-01-01T01:00:00Z', 'action' => 'click' }]
      end

      let(:acts_b) do
        Array.new(5) do |i|
          { 'timestamp' => "2025-01-02T0#{i}:00:00Z", 'action' => 'view' }
        end
      end

      let(:acts_c) do
        [{ 'timestamp' => '2025-01-03T00:00:00Z', 'action' => 'signup' }]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('a').and_return(acts_a)
        allow(reporter).to receive(:fetch_user_activities).with('b').and_return(acts_b)
        allow(reporter).to receive(:fetch_user_activities).with('c').and_return(acts_c)

        allow(reporter).to receive(:fetch_activity_stats).with('a').and_return(
          {
            total_actions: 2,
            unique_actions: 2,
            action_counts: { 'view' => 1, 'click' => 1 },
            first_activity: acts_a.first['timestamp'],
            last_activity: acts_a.last['timestamp'],
            most_frequent: 'view'
          }
        )

        allow(reporter).to receive(:fetch_activity_stats).with('b').and_return(
          {
            total_actions: 5,
            unique_actions: 1,
            action_counts: { 'view' => 5 },
            first_activity: acts_b.first['timestamp'],
            last_activity: acts_b.last['timestamp'],
            most_frequent: 'view'
          }
        )

        allow(reporter).to receive(:fetch_activity_stats).with('c').and_return(
          {
            total_actions: 1,
            unique_actions: 1,
            action_counts: { 'signup' => 1 },
            first_activity: acts_c.first['timestamp'],
            last_activity: acts_c.last['timestamp'],
            most_frequent: 'signup'
          }
        )

        allow(reporter).to receive(:fetch_user_score).with(acts_a).and_return(50.0)
        allow(reporter).to receive(:fetch_user_score).with(acts_b).and_return(70.5)
        allow(reporter).to receive(:fetch_user_score).with(acts_c).and_return(30.2)
      end

      it 'returns comparisons sorted by engagement score descending with correct aggregates' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(['b', 'a', 'c'])

        top = result[:comparisons].first
        expect(top[:user_id]).to eq('b')
        expect(top[:total_actions]).to eq(5)
        expect(top[:engagement_score]).to eq(70.5)
        expect(top[:most_frequent_action]).to eq('view')

        expect(result[:top_user]).to eq('b')
        expect(result[:average_score]).to eq(50.23)
      end
    end
  end
end
