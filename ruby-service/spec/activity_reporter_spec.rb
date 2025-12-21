require 'spec_helper'
require 'json'
require 'time'
require 'tmpdir'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  describe '#initialize' do
    it 'accepts custom service URLs without error' do
      expect do
        described_class.new(go_service_url: 'http://go.example', python_service_url: 'http://py.example')
      end.not_to raise_error
    end
  end

  describe '#generate_report' do
    let(:reporter) { described_class.new }
    let(:user_id) { 'user-123' }
    let(:fixed_time) { Time.utc(2023, 5, 3, 12, 0, 0) }

    before do
      allow(Time).to receive(:now).and_return(fixed_time)
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report with the correct message and timestamp' do
        result = reporter.generate_report(user_id)
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with activities and stats present' do
      let(:activities) do
        [
          { 'timestamp' => '2023-05-01T10:15:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-05-01T11:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-05-02T09:00:00Z', 'action' => 'click' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 2,
          action_counts: { 'click' => 2, 'view' => 1 },
          first_activity: '2023-05-01T10:15:00Z',
          last_activity: '2023-05-02T09:00:00Z',
          most_frequent: 'click'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'streak', 'description' => 'Daily usage', 'confidence' => 0.9 }
        ]
      end

      let(:anomalies) do
        [{ 'id' => 1 }, { 'id' => 2 }]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(76.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a report with summary, patterns, anomalies, timeline, and insights' do
        result = reporter.generate_report(user_id, group_by: :day)
        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(fixed_time.iso8601)

        expect(result[:summary][:total_actions]).to eq(3)
        expect(result[:summary][:unique_actions]).to eq(2)
        expect(result[:summary][:engagement_score]).to eq(76.0)
        expect(result[:summary][:first_activity]).to eq('2023-05-01T10:15:00Z')
        expect(result[:summary][:last_activity]).to eq('2023-05-02T09:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'click' => 2, 'view' => 1 })

        expect(result[:patterns]).to eq([
                                          { type: 'streak', description: 'Daily usage', confidence: 0.9 }
                                        ])

        expect(result[:anomalies]).to eq(anomalies)

        periods = result[:timeline].map { |t| t[:period] }
        expect(periods).to eq(%w[2023-05-01 2023-05-02])

        day1 = result[:timeline].find { |t| t[:period] == '2023-05-01' }
        expect(day1[:total_actions]).to eq(2)
        expect(day1[:actions]).to eq({ 'click' => 1, 'view' => 1 })
        expect(day1[:first_timestamp]).to eq('2023-05-01T10:15:00Z')
        expect(day1[:last_timestamp]).to eq('2023-05-01T11:00:00Z')

        day2 = result[:timeline].find { |t| t[:period] == '2023-05-02' }
        expect(day2[:total_actions]).to eq(1)
        expect(day2[:actions]).to eq({ 'click' => 1 })
        expect(day2[:first_timestamp]).to eq('2023-05-02T09:00:00Z')
        expect(day2[:last_timestamp]).to eq('2023-05-02T09:00:00Z')

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('2 anomalous activities detected - review recommended')
      end

      it 'forwards group_by option to timeline generation (hour buckets)' do
        result = reporter.generate_report(user_id, group_by: :hour)
        periods = result[:timeline].map { |t| t[:period] }
        expect(periods).to eq(['2023-05-01 10:00', '2023-05-01 11:00', '2023-05-02 09:00'])
      end
    end

    context 'with low engagement and no extras' do
      let(:activities) do
        [
          { 'timestamp' => '2023-05-01T10:15:00Z', 'action' => 'click' }
        ]
      end

      let(:stats) do
        {
          total_actions: 1,
          unique_actions: 1,
          action_counts: { 'click' => 1 },
          first_activity: '2023-05-01T10:15:00Z',
          last_activity: '2023-05-01T10:15:00Z',
          most_frequent: 'click'
        }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return([])
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(10.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([])
      end

      it 'returns only the low engagement insight' do
        result = reporter.generate_report(user_id)
        expect(result[:insights]).to include('Low engagement - consider re-engagement strategies')
        expect(result[:insights].any? { |s| s.include?('Diverse') }).to eq(false)
        expect(result[:insights].any? { |s| s.include?('behavioral') }).to eq(false)
        expect(result[:insights].any? { |s| s.include?('anomalous') }).to eq(false)
        expect(result[:insights].any? { |s| s.include?('Power user') }).to eq(false)
      end
    end

    context 'with thresholds triggering all insight types' do
      let(:activities) do
        Array.new(101) do |i|
          { 'timestamp' => "2023-05-0#{(i % 5) + 1}T10:00:00Z", 'action' => "a#{i % 12}" }
        end
      end

      let(:stats) do
        {
          total_actions: 101,
          unique_actions: 11,
          action_counts: Hash[(0..11).map { |i| ["a#{i}", i == 11 ? 6 : 8] }],
          first_activity: '2023-05-01T10:00:00Z',
          last_activity: '2023-05-05T10:00:00Z',
          most_frequent: 'a0'
        }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return([
                                                                                           {
                                                                                             'pattern_type' => 'pattern1', 'description' => 'desc1', 'confidence' => 0.8
                                                                                           },
                                                                                           {
                                                                                             'pattern_type' => 'pattern2', 'description' => 'desc2', 'confidence' => 0.7
                                                                                           },
                                                                                           {
                                                                                             'pattern_type' => 'pattern3', 'description' => 'desc3', 'confidence' => 0.6
                                                                                           }
                                                                                         ])
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(90.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([{}, {}, {}])
      end

      it 'includes all applicable insights' do
        result = reporter.generate_report(user_id)
        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('3 anomalous activities detected - review recommended')
        expect(result[:insights]).to include('Power user - high volume of activities')
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) { described_class.new }

    context 'when activities are empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([], :day)).to eq([])
      end
    end

    context 'grouping by day with action breakdown and ordering' do
      let(:activities) do
        [
          { 'timestamp' => '2023-05-01T11:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-05-01T10:15:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-05-02T09:00:00Z', 'action' => 'click' }
        ]
      end

      it 'groups by day and sorts periods, preserving first/last timestamps based on input order' do
        timeline = reporter.format_timeline(activities, :day)
        periods = timeline.map { |t| t[:period] }
        expect(periods).to eq(%w[2023-05-01 2023-05-02])

        day1 = timeline[0]
        expect(day1[:total_actions]).to eq(2)
        expect(day1[:actions]).to eq({ 'view' => 1, 'click' => 1 })
        expect(day1[:first_timestamp]).to eq('2023-05-01T11:00:00Z')
        expect(day1[:last_timestamp]).to eq('2023-05-01T10:15:00Z')

        day2 = timeline[1]
        expect(day2[:total_actions]).to eq(1)
        expect(day2[:actions]).to eq({ 'click' => 1 })
        expect(day2[:first_timestamp]).to eq('2023-05-02T09:00:00Z')
        expect(day2[:last_timestamp]).to eq('2023-05-02T09:00:00Z')
      end
    end

    context 'grouping by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2023-05-01T10:15:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-05-01T10:45:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-05-01T11:00:00Z', 'action' => 'click' }
        ]
      end

      it 'groups by hour' do
        timeline = reporter.format_timeline(activities, :hour)
        periods = timeline.map { |t| t[:period] }
        expect(periods).to eq(['2023-05-01 10:00', '2023-05-01 11:00'])
        hour10 = timeline.find { |t| t[:period] == '2023-05-01 10:00' }
        expect(hour10[:total_actions]).to eq(2)
        expect(hour10[:actions]).to eq({ 'click' => 1, 'view' => 1 })
      end
    end

    context 'grouping by week and month' do
      let(:activities) do
        [
          { 'timestamp' => '2023-05-01T00:01:00Z', 'action' => 'a' },
          { 'timestamp' => '2023-05-08T00:01:00Z', 'action' => 'b' },
          { 'timestamp' => '2023-06-01T00:01:00Z', 'action' => 'c' }
        ]
      end

      it 'groups by ISO week' do
        timeline = reporter.format_timeline(activities, :week)
        periods = timeline.map { |t| t[:period] }
        expect(periods).to eq(%w[2023-W18 2023-W19 2023-W22])
      end

      it 'groups by month' do
        timeline = reporter.format_timeline(activities, :month)
        periods = timeline.map { |t| t[:period] }
        expect(periods).to eq(%w[2023-05 2023-06])
      end
    end

    context 'with invalid timestamps' do
      let(:activities) do
        [
          { 'timestamp' => 'not-a-timestamp', 'action' => 'view' }
        ]
      end

      it 'falls back to Time.now for grouping' do
        fixed_now = Time.utc(2023, 1, 2, 3, 4, 5)
        allow(Time).to receive(:now).and_return(fixed_now)
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.size).to eq(1)
        expect(timeline.first[:period]).to eq('2023-01-02')
      end
    end

    context 'with unknown group_by, defaults to day' do
      let(:activities) do
        [
          { 'timestamp' => '2023-05-01T10:15:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-05-01T11:15:00Z', 'action' => 'view' }
        ]
      end

      it 'uses day grouping when group_by is unknown' do
        timeline = reporter.format_timeline(activities, :unknown)
        expect(timeline.map { |t| t[:period] }).to eq(['2023-05-01'])
      end
    end
  end

  describe '#export_to_json' do
    let(:reporter) { described_class.new }
    let(:report) do
      {
        user_id: 'u1',
        generated_at: '2023-05-03T12:00:00Z',
        summary: { total_actions: 1, unique_actions: 1, engagement_score: 10.0, first_activity: 'x',
                   last_activity: 'y' },
        action_breakdown: { 'click' => 1 },
        patterns: [],
        anomalies: [],
        timeline: [],
        insights: ['Low engagement - consider re-engagement strategies']
      }
    end

    context 'when filepath is provided' do
      it 'writes the file and returns success with path and size' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to eq(true)
          expect(result[:filepath]).to eq(path)
          expected_size = JSON.pretty_generate(report).bytesize
          expect(result[:size]).to eq(expected_size)
          parsed = JSON.parse(File.read(path))
          expect(parsed['user_id']).to eq('u1')
        end
      end
    end

    context 'when filepath is not provided' do
      it 'returns success with JSON data' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to eq(true)
        expect(result[:data]).to be_a(String)
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq('u1')
      end
    end

    context 'when writing fails' do
      it 'returns an error result' do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        result = reporter.export_to_json(report, '/unwritable/path/report.json')
        expect(result[:success]).to eq(false)
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    let(:reporter) { described_class.new }

    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['u1'])
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with multiple users, sorts by engagement score and computes average' do
      before do
        expect(reporter).to receive(:fetch_user_activities).with('u1').and_return([{ 'timestamp' => 'x',
                                                                                     'action' => 'a' }])
        expect(reporter).to receive(:fetch_activity_stats).with('u1').and_return({
                                                                                   total_actions: 10, unique_actions: 2, action_counts: {}, first_activity: 'x', last_activity: 'y', most_frequent: 'click'
                                                                                 })
        expect(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => 'x', 'action' => 'a' }]).and_return(30.0)

        expect(reporter).to receive(:fetch_user_activities).with('u2').and_return([{ 'timestamp' => 'x',
                                                                                     'action' => 'a' }])
        expect(reporter).to receive(:fetch_activity_stats).with('u2').and_return({
                                                                                   total_actions: 20, unique_actions: 3, action_counts: {}, first_activity: 'x', last_activity: 'y', most_frequent: 'like'
                                                                                 })
        expect(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => 'x', 'action' => 'a' }]).and_return(80.5)

        expect(reporter).to receive(:fetch_user_activities).with('u3').and_return([{ 'timestamp' => 'x',
                                                                                     'action' => 'a' }])
        expect(reporter).to receive(:fetch_activity_stats).with('u3').and_return({
                                                                                   total_actions: 5, unique_actions: 1, action_counts: {}, first_activity: 'x', last_activity: 'y', most_frequent: 'view'
                                                                                 })
        expect(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => 'x', 'action' => 'a' }]).and_return(55.0)
      end

      it 'returns sorted comparisons, top_user, and average_score' do
        result = reporter.compare_users(%w[u1 u2 u3])
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[u2 u3 u1])
        expect(result[:comparisons].first[:most_frequent]).to eq('like')
        expect(result[:comparisons].first[:total_actions]).to eq(20)
        expect(result[:comparisons].first[:engagement_score]).to eq(80.5)
        expect(result[:top_user]).to eq('u2')
        expect(result[:average_score]).to eq(55.17)
      end
    end

    context 'with equal engagement scores preserves input order' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([])
        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({
                                                                                  total_actions: 1, unique_actions: 1, action_counts: {}, first_activity: 'x', last_activity: 'y', most_frequent: 'a'
                                                                                })
        allow(reporter).to receive(:fetch_user_score).with([]).and_return(50.0)

        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([])
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({
                                                                                  total_actions: 2, unique_actions: 1, action_counts: {}, first_activity: 'x', last_activity: 'y', most_frequent: 'b'
                                                                                })
        allow(reporter).to receive(:fetch_user_score).with([]).and_return(50.0)
      end

      it 'keeps original order for ties' do
        result = reporter.compare_users(%w[u1 u2])
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[u1 u2])
        expect(result[:top_user]).to eq('u1')
      end
    end
  end
end
