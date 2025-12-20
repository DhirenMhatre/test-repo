require 'spec_helper'
require 'time'
require 'json'
require 'tmpdir'
require 'rails_helper'

RSpec.describe ActivityReporter do
  let(:reporter) { described_class.new }
  let(:fixed_time) { Time.utc(2023, 1, 1, 12, 34, 56) }

  before do
    allow(Time).to receive(:now).and_return(fixed_time)
  end

  describe '#generate_report' do
    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('user-1').and_return([])
      end

      it 'returns an error report' do
        result = reporter.generate_report('user-1')
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with activities and valid stats' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2023-01-01T10:00:00Z' },
          { 'action' => 'click', 'timestamp' => '2023-01-01T11:00:00Z' },
          { 'action' => 'login', 'timestamp' => '2023-01-02T09:00:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 2,
          action_counts: { 'login' => 2, 'click' => 1 },
          first_activity: '2023-01-01T10:00:00Z',
          last_activity: '2023-01-02T09:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'sequence', 'description' => 'Login then click', 'confidence' => 0.9 },
          { 'pattern_type' => 'daily', 'description' => 'Morning logins', 'confidence' => 0.8 },
          { 'pattern_type' => 'repeat', 'description' => 'Repeated login', 'confidence' => 0.85 }
        ]
      end

      let(:anomalies) do
        [
          { 'id' => 1, 'reason' => 'suspicious' },
          { 'id' => 2, 'reason' => 'threshold' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('user-1').and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with('user-1').and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(80.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'returns a rich report with summary, patterns, timeline (day grouping), and insights' do
        result = reporter.generate_report('user-1')

        expect(result[:user_id]).to eq('user-1')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)

        expect(result[:summary][:total_actions]).to eq(3)
        expect(result[:summary][:unique_actions]).to eq(2)
        expect(result[:summary][:engagement_score]).to eq(80.0)
        expect(result[:summary][:first_activity]).to eq('2023-01-01T10:00:00Z')
        expect(result[:summary][:last_activity]).to eq('2023-01-02T09:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'login' => 2, 'click' => 1 })

        expect(result[:patterns]).to contain_exactly(
          { type: 'sequence', description: 'Login then click', confidence: 0.9 },
          { type: 'daily', description: 'Morning logins', confidence: 0.8 },
          { type: 'repeat', description: 'Repeated login', confidence: 0.85 }
        )

        expect(result[:anomalies]).to eq(anomalies)

        expect(result[:timeline].size).to eq(2)
        jan1 = result[:timeline].find { |e| e[:period] == '2023-01-01' }
        jan2 = result[:timeline].find { |e| e[:period] == '2023-01-02' }

        expect(jan1[:total_actions]).to eq(2)
        expect(jan1[:actions]).to eq({ 'login' => 1, 'click' => 1 })
        expect(jan1[:first_timestamp]).to eq('2023-01-01T10:00:00Z')
        expect(jan1[:last_timestamp]).to eq('2023-01-01T11:00:00Z')

        expect(jan2[:total_actions]).to eq(1)
        expect(jan2[:actions]).to eq({ 'login' => 1 })
        expect(jan2[:first_timestamp]).to eq('2023-01-02T09:00:00Z')
        expect(jan2[:last_timestamp]).to eq('2023-01-02T09:00:00Z')

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('2 anomalous activities detected - review recommended')
        expect(result[:insights]).not_to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).not_to include('Power user - high volume of activities')
      end

      it 'supports custom grouping (month)' do
        result = reporter.generate_report('user-1', group_by: :month)
        expect(result[:timeline].size).to eq(1)
        entry = result[:timeline].first
        expect(entry[:period]).to eq('2023-01')
        expect(entry[:total_actions]).to eq(3)
        expect(entry[:actions]).to eq({ 'login' => 2, 'click' => 1 })
        expect(entry[:first_timestamp]).to eq('2023-01-01T10:00:00Z')
        expect(entry[:last_timestamp]).to eq('2023-01-02T09:00:00Z')
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities are empty' do
      it 'returns an empty array' do
        expect(reporter.format_timeline([])).to eq([])
      end
    end

    context 'with day grouping (default)' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2023-03-10T09:00:00Z' },
          { 'action' => 'purchase', 'timestamp' => '2023-03-11T10:00:00Z' },
          { 'action' => 'login', 'timestamp' => '2023-03-11T11:00:00Z' }
        ]
      end

      it 'groups entries by day, counts actions, and sorts by day' do
        timeline = reporter.format_timeline(activities, :day)
        expect(timeline.map { |e| e[:period] }).to eq(%w[2023-03-10 2023-03-11])

        day1 = timeline[0]
        day2 = timeline[1]

        expect(day1[:total_actions]).to eq(1)
        expect(day1[:actions]).to eq({ 'login' => 1 })
        expect(day1[:first_timestamp]).to eq('2023-03-10T09:00:00Z')
        expect(day1[:last_timestamp]).to eq('2023-03-10T09:00:00Z')

        expect(day2[:total_actions]).to eq(2)
        expect(day2[:actions]).to eq({ 'purchase' => 1, 'login' => 1 })
        expect(day2[:first_timestamp]).to eq('2023-03-11T10:00:00Z')
        expect(day2[:last_timestamp]).to eq('2023-03-11T11:00:00Z')
      end
    end

    context 'with hour grouping' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2023-03-10T09:15:00Z' },
          { 'action' => 'login', 'timestamp' => '2023-03-10T10:45:00Z' }
        ]
      end

      it 'groups by hour using the HH:00 format' do
        timeline = reporter.format_timeline(activities, :hour)
        expect(timeline.map { |e| e[:period] }).to eq(['2023-03-10 09:00', '2023-03-10 10:00'])

        expect(timeline[0][:actions]).to eq({ 'login' => 1 })
        expect(timeline[1][:actions]).to eq({ 'login' => 1 })
      end
    end

    context 'with week grouping' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2023-01-02T12:00:00Z' },
          { 'action' => 'login', 'timestamp' => '2023-01-06T12:00:00Z' }
        ]
      end

      it 'groups by ISO week' do
        timeline = reporter.format_timeline(activities, :week)
        expect(timeline.size).to eq(1)
        expect(timeline.first[:period]).to match(/\A2023-W\d{2}\z/)
        expect(timeline.first[:total_actions]).to eq(2)
      end
    end

    context 'with invalid timestamps' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => 'invalid' },
          { 'action' => 'click', 'timestamp' => '2023-01-05T12:00:00Z' }
        ]
      end

      it 'falls back to Time.now for grouping and preserves original timestamps' do
        timeline = reporter.format_timeline(activities, :day)
        periods = timeline.map { |e| e[:period] }
        expect(periods).to include('2023-01-01')
        expect(periods).to include('2023-01-05')

        invalid_period_entry = timeline.find { |e| e[:period] == '2023-01-01' }
        expect(invalid_period_entry[:actions]).to eq({ 'login' => 1 })
        expect(invalid_period_entry[:first_timestamp]).to eq('invalid')
        expect(invalid_period_entry[:last_timestamp]).to eq('invalid')
      end
    end

    context 'with unknown grouping key' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2023-04-01T09:00:00Z' },
          { 'action' => 'login', 'timestamp' => '2023-04-02T09:00:00Z' }
        ]
      end

      it 'defaults to day grouping' do
        timeline = reporter.format_timeline(activities, :unknown)
        expect(timeline.map { |e| e[:period] }).to eq(%w[2023-04-01 2023-04-02])
      end
    end
  end

  describe '#export_to_json' do
    let(:report_hash) do
      {
        user_id: 'user-1',
        generated_at: fixed_time.iso8601,
        summary: { total_actions: 1, unique_actions: 1, engagement_score: 10.0, first_activity: 't1',
                   last_activity: 't1' },
        action_breakdown: { 'login' => 1 },
        patterns: [],
        anomalies: [],
        timeline: [],
        insights: []
      }
    end

    context 'when filepath is not provided' do
      it 'returns a JSON string in the data field' do
        result = reporter.export_to_json(report_hash)
        expect(result[:success]).to be true
        expect(result[:data]).to be_a(String)
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq('user-1')
      end
    end

    context 'when filepath is provided' do
      it 'writes the JSON to the file and returns metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report_hash, path)
          expect(result[:success]).to be true
          expect(result[:filepath]).to eq(path)
          expect(File.exist?(path)).to be true
          contents = File.read(path)
          expect(contents).to eq(JSON.pretty_generate(report_hash))
          expect(result[:size]).to eq(contents.bytesize)
        end
      end
    end

    context 'when writing to file raises an error' do
      it 'returns a failure with error message' do
        allow(File).to receive(:write).and_raise(StandardError.new('boom'))
        result = reporter.export_to_json(report_hash, '/tmp/somewhere.json')
        expect(result[:success]).to be false
        expect(result[:error]).to eq('boom')
      end
    end
  end

  describe '#compare_users' do
    context 'when less than two user IDs are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with two users' do
      let(:u1_id) { 'u1' }
      let(:u2_id) { 'u2' }
      let(:u1_activities) do
        [
          { 'action' => 'login', 'timestamp' => '2023-01-01T09:00:00Z' }
        ]
      end
      let(:u2_activities) do
        [
          { 'action' => 'click', 'timestamp' => '2023-01-03T10:00:00Z' }
        ]
      end
      let(:u1_stats) do
        {
          total_actions: 5,
          unique_actions: 3,
          action_counts: { 'login' => 3, 'click' => 2 },
          first_activity: '2023-01-01T00:00:00Z',
          last_activity: '2023-01-10T00:00:00Z',
          most_frequent: 'login'
        }
      end
      let(:u2_stats) do
        {
          total_actions: 3,
          unique_actions: 2,
          action_counts: { 'click' => 3 },
          first_activity: '2023-01-03T00:00:00Z',
          last_activity: '2023-01-05T00:00:00Z',
          most_frequent: 'click'
        }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(u1_id).and_return(u1_activities)
        allow(reporter).to receive(:fetch_user_activities).with(u2_id).and_return(u2_activities)
        allow(reporter).to receive(:fetch_activity_stats).with(u1_id).and_return(u1_stats)
        allow(reporter).to receive(:fetch_activity_stats).with(u2_id).and_return(u2_stats)
        allow(reporter).to receive(:fetch_user_score).with(u1_activities).and_return(70.5)
        allow(reporter).to receive(:fetch_user_score).with(u2_activities).and_return(82.25)
      end

      it 'returns comparisons sorted by engagement score with top_user and average_score' do
        result = reporter.compare_users([u1_id, u2_id])
        expect(result[:total_users]).to eq(2)
        expect(result[:comparisons].size).to eq(2)
        expect(result[:comparisons].first[:user_id]).to eq(u2_id)
        expect(result[:comparisons].first[:engagement_score]).to eq(82.25)
        expect(result[:comparisons].last[:user_id]).to eq(u1_id)
        expect(result[:comparisons].last[:engagement_score]).to eq(70.5)
        expect(result[:top_user]).to eq(u2_id)
        expect(result[:average_score]).to eq(((70.5 + 82.25) / 2.0).round(2))
      end

      it 'includes most_frequent_action and total_actions per user' do
        result = reporter.compare_users([u1_id, u2_id])
        comp_u1 = result[:comparisons].find { |c| c[:user_id] == u1_id }
        comp_u2 = result[:comparisons].find { |c| c[:user_id] == u2_id }
        expect(comp_u1[:most_frequent_action]).to eq('login')
        expect(comp_u1[:total_actions]).to eq(5)
        expect(comp_u2[:most_frequent_action]).to eq('click')
        expect(comp_u2[:total_actions]).to eq(3)
      end
    end

    context 'with more than two users' do
      let(:ids) { %w[a b c] }
      let(:acts_a) { [{ 'action' => 'x', 'timestamp' => '2023-01-01T00:00:00Z' }] }
      let(:acts_b) { [{ 'action' => 'y', 'timestamp' => '2023-01-01T00:00:00Z' }] }
      let(:acts_c) { [{ 'action' => 'z', 'timestamp' => '2023-01-01T00:00:00Z' }] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with('a').and_return(acts_a)
        allow(reporter).to receive(:fetch_user_activities).with('b').and_return(acts_b)
        allow(reporter).to receive(:fetch_user_activities).with('c').and_return(acts_c)

        allow(reporter).to receive(:fetch_activity_stats).with('a').and_return({ total_actions: 1, unique_actions: 1,
                                                                                 action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'x' })
        allow(reporter).to receive(:fetch_activity_stats).with('b').and_return({ total_actions: 2, unique_actions: 1,
                                                                                 action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'y' })
        allow(reporter).to receive(:fetch_activity_stats).with('c').and_return({ total_actions: 3, unique_actions: 1,
                                                                                 action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'z' })

        allow(reporter).to receive(:fetch_user_score).with(acts_a).and_return(10.0)
        allow(reporter).to receive(:fetch_user_score).with(acts_b).and_return(50.0)
        allow(reporter).to receive(:fetch_user_score).with(acts_c).and_return(30.0)
      end

      it 'sorts all users by score descending and computes average' do
        result = reporter.compare_users(ids)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[b c a])
        expect(result[:top_user]).to eq('b')
        expect(result[:average_score]).to eq(((10.0 + 50.0 + 30.0) / 3.0).round(2))
      end
    end
  end
end
