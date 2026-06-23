require 'time'
require 'json'
require 'tmpdir'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new
  end

  describe '#generate_report' do
    context 'when no activities exist' do
      it 'returns an error report with message and generated_at' do
        allow(reporter).to receive(:fetch_user_activities).with(123).and_return([])
        fixed_now = Time.parse('2025-01-02T03:04:05Z')
        allow(Time).to receive(:now).and_return(fixed_now)

        result = reporter.generate_report(123)

        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_now.iso8601)
      end
    end

    context 'with activities present' do
      let(:user_id) do
        42
      end

      let(:activities) do
        [
          { 'timestamp' => '2024-05-01T10:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2024-05-01T11:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2024-05-02T09:30:00Z', 'action' => 'logout' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 3,
          action_counts: { 'login' => 1, 'click' => 1, 'logout' => 1 },
          first_activity: '2024-05-01T10:00:00Z',
          last_activity: '2024-05-02T09:30:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'daily', 'description' => 'morning activity', 'confidence' => 0.9 },
          { 'pattern_type' => 'weekly', 'description' => 'weekday use', 'confidence' => 0.8 }
        ]
      end

      let(:anomalies) do
        ['suspicious login']
      end

      let(:user_score) do
        76.0
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
        fixed_now = Time.parse('2024-06-01T12:00:00Z')
        allow(Time).to receive(:now).and_return(fixed_now)
      end

      it 'builds a comprehensive report with default daily grouping' do
        result = reporter.generate_report(user_id)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(Time.now.iso8601)
        expect(result[:summary]).to include(
          total_actions: 3,
          unique_actions: 3,
          engagement_score: user_score,
          first_activity: stats[:first_activity],
          last_activity: stats[:last_activity]
        )
        expect(result[:action_breakdown]).to eq(stats[:action_counts])
        expected_patterns = patterns.map do |p|
          { type: p['pattern_type'], description: p['description'], confidence: p['confidence'] }
        end
        expect(result[:patterns]).to eq(expected_patterns)
        expect(result[:anomalies]).to eq(anomalies)

        periods = result[:timeline].map { |t| t[:period] }
        expect(periods).to eq(['2024-05-01', '2024-05-02'])
        may1 = result[:timeline].find { |t| t[:period] == '2024-05-01' }
        expect(may1[:total_actions]).to eq(2)
        expect(may1[:actions]).to eq({ 'login' => 1, 'click' => 1 })

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(result[:insights]).not_to include('Power user - high volume of activities')
      end

      it 'groups timeline by month when specified' do
        r = reporter.generate_report(user_id, group_by: :month)
        expect(r[:timeline].map { |t| t[:period] }).to eq(['2024-05'])
      end
    end

    context 'insights with moderate engagement and diverse/high volume activity' do
      let(:user_id) do
        7
      end

      let(:activities) do
        [
          { 'timestamp' => '2024-01-10T08:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2024-01-11T09:00:00Z', 'action' => 'b' }
        ]
      end

      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 11,
          action_counts: { 'a' => 1, 'b' => 1 },
          first_activity: '2024-01-10T08:00:00Z',
          last_activity: '2024-01-11T09:00:00Z',
          most_frequent: 'a'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'p1', 'description' => 'd1', 'confidence' => 0.5 },
          { 'pattern_type' => 'p2', 'description' => 'd2', 'confidence' => 0.6 },
          { 'pattern_type' => 'p3', 'description' => 'd3', 'confidence' => 0.7 }
        ]
      end

      let(:user_score) do
        51.0
      end

      let(:anomalies) do
        []
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'includes moderate engagement, diverse profile, clear patterns, and power user insights' do
        result = reporter.generate_report(user_id)

        expect(result[:insights]).to include('Moderately engaged user with regular activity')
        expect(result[:insights]).to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('Power user - high volume of activities')
        expect(result[:insights]).not_to include('Highly engaged user with strong activity patterns')
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities is empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([])).to eq([])
      end
    end

    context 'grouping by day' do
      it 'groups actions per day with sorted periods and correct counts' do
        activities = [
          { 'timestamp' => '2024-03-02T12:00:00Z', 'action' => 'b' },
          { 'timestamp' => '2024-03-01T09:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2024-03-01T10:00:00Z', 'action' => 'a' }
        ]

        timeline = reporter.format_timeline(activities, :day)

        expect(timeline.map { |e| e[:period] }).to eq(['2024-03-01', '2024-03-02'])
        day1 = timeline[0]
        day2 = timeline[1]
        expect(day1[:total_actions]).to eq(2)
        expect(day1[:actions]).to eq({ 'a' => 2 })
        expect(day1[:first_timestamp]).to eq('2024-03-01T09:00:00Z')
        expect(day1[:last_timestamp]).to eq('2024-03-01T10:00:00Z')
        expect(day2[:total_actions]).to eq(1)
        expect(day2[:actions]).to eq({ 'b' => 1 })
      end
    end

    context 'grouping by hour' do
      it 'groups actions per hour' do
        activities = [
          { 'timestamp' => '2024-04-01T10:15:00Z', 'action' => 'a' },
          { 'timestamp' => '2024-04-01T10:45:00Z', 'action' => 'b' },
          { 'timestamp' => '2024-04-01T11:00:00Z', 'action' => 'b' }
        ]

        timeline = reporter.format_timeline(activities, :hour)

        expect(timeline.map { |e| e[:period] }).to eq(['2024-04-01 10:00', '2024-04-01 11:00'])
        h10 = timeline[0]
        h11 = timeline[1]
        expect(h10[:total_actions]).to eq(2)
        expect(h10[:actions]).to eq({ 'a' => 1, 'b' => 1 })
        expect(h11[:total_actions]).to eq(1)
        expect(h11[:actions]).to eq({ 'b' => 1 })
      end
    end

    context 'grouping by week' do
      it 'groups actions per ISO week' do
        t1 = '2024-05-01T10:00:00Z'
        t2 = '2024-05-03T12:00:00Z'
        week_label = Time.parse(t1).strftime('%Y-W%V')
        activities = [
          { 'timestamp' => t1, 'action' => 'x' },
          { 'timestamp' => t2, 'action' => 'y' }
        ]

        timeline = reporter.format_timeline(activities, :week)

        expect(timeline.map { |e| e[:period] }).to eq([week_label])
        expect(timeline.first[:actions]).to eq({ 'x' => 1, 'y' => 1 })
        expect(timeline.first[:total_actions]).to eq(2)
      end
    end

    context 'grouping by month' do
      it 'groups actions per month' do
        activities = [
          { 'timestamp' => '2024-06-01T00:00:00Z', 'action' => 'm1' },
          { 'timestamp' => '2024-06-30T23:59:59Z', 'action' => 'm2' },
          { 'timestamp' => '2024-07-01T00:00:00Z', 'action' => 'm3' }
        ]

        timeline = reporter.format_timeline(activities, :month)

        expect(timeline.map { |e| e[:period] }).to eq(['2024-06', '2024-07'])
        june = timeline[0]
        july = timeline[1]
        expect(june[:total_actions]).to eq(2)
        expect(june[:actions]).to eq({ 'm1' => 1, 'm2' => 1 })
        expect(july[:total_actions]).to eq(1)
        expect(july[:actions]).to eq({ 'm3' => 1 })
      end
    end

    context 'with an invalid timestamp' do
      it 'falls back to grouping by current time' do
        fixed_now = Time.parse('2024-05-05T00:00:00Z')
        allow(Time).to receive(:now).and_return(fixed_now)
        activities = [
          { 'timestamp' => 'not-a-time', 'action' => 'bad' }
        ]

        timeline = reporter.format_timeline(activities, :day)

        expect(timeline.size).to eq(1)
        expect(timeline.first[:period]).to eq(fixed_now.strftime('%Y-%m-%d'))
        expect(timeline.first[:first_timestamp]).to eq('not-a-time')
        expect(timeline.first[:actions]).to eq({ 'bad' => 1 })
      end
    end
  end

  describe '#export_to_json' do
    let(:report) do
      { a: 1, b: { c: 2 } }
    end

    context 'without filepath' do
      it 'returns JSON string data' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to eq(true)
        expect(result[:data]).to eq(JSON.pretty_generate(report))
        expect(result[:data]).to include("\n")
      end
    end

    context 'with filepath' do
      it 'writes to the file and returns metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)

          expect(result[:success]).to eq(true)
          expect(result[:filepath]).to eq(path)
          expect(result[:size]).to eq(JSON.pretty_generate(report).bytesize)
          content = File.read(path)
          expect(content).to eq(JSON.pretty_generate(report))
        end
      end
    end

    context 'when writing fails' do
      it 'returns an error hash' do
        allow(File).to receive(:write).and_raise(StandardError.new('boom'))

        result = reporter.export_to_json(report, '/unwritable/path.json')

        expect(result[:success]).to eq(false)
        expect(result[:error]).to eq('boom')
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than two users provided' do
      it 'returns an error report' do
        fixed_now = Time.parse('2025-02-01T00:00:00Z')
        allow(Time).to receive(:now).and_return(fixed_now)

        result = reporter.compare_users(['only_one'])

        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_now.iso8601)
      end
    end

    context 'with multiple users' do
      let(:user_ids) do
        %w[u1 u2 u3]
      end

      it 'compares users and sorts by engagement score descending' do
        activities_u1 = [{ 'timestamp' => '2024-01-01T00:00:00Z', 'action' => 'view' }]
        activities_u2 = [
          { 'timestamp' => '2024-01-01T00:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2024-01-02T00:00:00Z', 'action' => 'click' }
        ]
        activities_u3 = []

        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return(activities_u1)
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return(activities_u2)
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return(activities_u3)

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({ total_actions: 5, unique_actions: 2, action_counts: {}, first_activity: 't1', last_activity: 't2', most_frequent: 'view' })
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({ total_actions: 10, unique_actions: 3, action_counts: {}, first_activity: 't1', last_activity: 't2', most_frequent: 'click' })
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return({ total_actions: 1, unique_actions: 1, action_counts: {}, first_activity: 't1', last_activity: 't2', most_frequent: 'view' })

        allow(reporter).to receive(:fetch_user_score).with(activities_u1).and_return(20.0)
        allow(reporter).to receive(:fetch_user_score).with(activities_u2).and_return(80.0)
        allow(reporter).to receive(:fetch_user_score).with(activities_u3).and_return(50.0)

        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:top_user]).to eq('u2')
        expect(result[:average_score]).to eq(50.0)

        comparisons = result[:comparisons]
        expect(comparisons.map { |c| c[:user_id] }).to eq(['u2', 'u3', 'u1'])
        expect(comparisons.find { |c| c[:user_id] == 'u2' }).to include(total_actions: 10, engagement_score: 80.0, most_frequent_action: 'click')
        expect(comparisons.find { |c| c[:user_id] == 'u1' }).to include(total_actions: 5, engagement_score: 20.0, most_frequent_action: 'view')
      end
    end
  end
end
