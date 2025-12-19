require 'spec_helper'
require 'json'
require 'time'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new
  end

  let(:fixed_time) do
    Time.parse('2025-01-15T12:34:56Z')
  end

  before do
    allow(Time).to receive(:now).and_return(fixed_time)
  end

  describe '#generate_report' do
    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('user-1').and_return([])
      end

      it 'returns an error report with a message' do
        result = reporter.generate_report('user-1')
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with activities and custom grouping' do
      let(:user_id) do
        'user-123'
      end

      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T10:15:00Z' },
          { 'action' => 'logout', 'timestamp' => '2025-01-01T15:30:00Z' },
          { 'action' => 'view', 'timestamp' => '2025-01-02T09:00:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 12,
          action_counts: { 'login' => 80, 'logout' => 40, 'view' => 30 },
          first_activity: '2025-01-01T10:15:00Z',
          last_activity: '2025-01-02T09:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'streak', 'description' => 'Daily login', 'confidence' => 0.92 },
          { 'pattern_type' => 'time_of_day', 'description' => 'Morning active', 'confidence' => 0.81 },
          { 'pattern_type' => 'sequence', 'description' => 'Login -> View -> Logout', 'confidence' => 0.88 }
        ]
      end

      let(:user_score) do
        82.5
      end

      let(:anomalies) do
        ['rare action', 'suspicious login']
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a comprehensive report including summary, timeline, patterns, and insights' do
        result = reporter.generate_report(user_id, group_by: :day)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(fixed_time.iso8601)

        expect(result[:summary][:total_actions]).to eq(150)
        expect(result[:summary][:unique_actions]).to eq(12)
        expect(result[:summary][:engagement_score]).to eq(82.5)
        expect(result[:summary][:first_activity]).to eq('2025-01-01T10:15:00Z')
        expect(result[:summary][:last_activity]).to eq('2025-01-02T09:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'login' => 80, 'logout' => 40, 'view' => 30 })

        expect(result[:patterns]).to eq([
                                          { type: 'streak', description: 'Daily login', confidence: 0.92 },
                                          { type: 'time_of_day', description: 'Morning active', confidence: 0.81 },
                                          { type: 'sequence', description: 'Login -> View -> Logout', confidence: 0.88 }
                                        ])

        expect(result[:anomalies]).to eq(['rare action', 'suspicious login'])

        expect(result[:timeline].length).to eq(2)
        expect(result[:timeline][0][:period]).to eq('2025-01-01')
        expect(result[:timeline][0][:total_actions]).to eq(2)
        expect(result[:timeline][0][:actions]).to eq({ 'login' => 1, 'logout' => 1 })
        expect(result[:timeline][0][:first_timestamp]).to eq('2025-01-01T10:15:00Z')
        expect(result[:timeline][0][:last_timestamp]).to eq('2025-01-01T15:30:00Z')

        expect(result[:timeline][1][:period]).to eq('2025-01-02')
        expect(result[:timeline][1][:total_actions]).to eq(1)
        expect(result[:timeline][1][:actions]).to eq({ 'view' => 1 })
        expect(result[:timeline][1][:first_timestamp]).to eq('2025-01-02T09:00:00Z')
        expect(result[:timeline][1][:last_timestamp]).to eq('2025-01-02T09:00:00Z')

        expect(result[:insights]).to eq([
                                          'Highly engaged user with strong activity patterns',
                                          'Diverse activity profile across multiple action types',
                                          'Clear behavioral patterns detected',
                                          '2 anomalous activities detected - review recommended',
                                          'Power user - high volume of activities'
                                        ])
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
          { 'action' => 'login', 'timestamp' => '2025-01-01T10:15:00Z' },
          { 'action' => 'logout', 'timestamp' => '2025-01-01T15:30:00Z' },
          { 'action' => 'view', 'timestamp' => '2025-01-02T09:00:00Z' }
        ]
      end

      it 'groups activities per hour and sorts by period' do
        result = reporter.format_timeline(activities, :hour)
        expect(result.map { |e| e[:period] }).to eq(['2025-01-01 10:00', '2025-01-01 15:00', '2025-01-02 09:00'])
        expect(result.map { |e| e[:total_actions] }).to eq([1, 1, 1])
        expect(result[0][:actions]).to eq({ 'login' => 1 })
        expect(result[1][:actions]).to eq({ 'logout' => 1 })
        expect(result[2][:actions]).to eq({ 'view' => 1 })
      end
    end

    context 'when grouping by day' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T10:15:00Z' },
          { 'action' => 'logout', 'timestamp' => '2025-01-01T15:30:00Z' },
          { 'action' => 'view', 'timestamp' => '2025-01-02T09:00:00Z' }
        ]
      end

      it 'groups activities per day correctly' do
        result = reporter.format_timeline(activities, :day)
        expect(result.length).to eq(2)
        expect(result[0][:period]).to eq('2025-01-01')
        expect(result[0][:total_actions]).to eq(2)
        expect(result[0][:first_timestamp]).to eq('2025-01-01T10:15:00Z')
        expect(result[0][:last_timestamp]).to eq('2025-01-01T15:30:00Z')
        expect(result[1][:period]).to eq('2025-01-02')
        expect(result[1][:total_actions]).to eq(1)
      end
    end

    context 'when grouping by week' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T10:15:00Z' },
          { 'action' => 'logout', 'timestamp' => '2025-01-01T15:30:00Z' },
          { 'action' => 'view', 'timestamp' => '2025-01-02T09:00:00Z' }
        ]
      end

      it 'groups activities into ISO weeks' do
        result = reporter.format_timeline(activities, :week)
        expect(result.length).to eq(1)
        expect(result.first[:period]).to match(/\A2025-W0?1\z/)
        expect(result.first[:total_actions]).to eq(3)
        expect(result.first[:actions]).to eq({ 'login' => 1, 'logout' => 1, 'view' => 1 })
      end
    end

    context 'when grouping by month' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T10:15:00Z' },
          { 'action' => 'logout', 'timestamp' => '2025-01-01T15:30:00Z' },
          { 'action' => 'view', 'timestamp' => '2025-01-02T09:00:00Z' }
        ]
      end

      it 'groups activities per month' do
        result = reporter.format_timeline(activities, :month)
        expect(result.length).to eq(1)
        expect(result.first[:period]).to eq('2025-01')
        expect(result.first[:total_actions]).to eq(3)
      end
    end

    context 'with invalid timestamps' do
      let(:now_for_parse) do
        Time.parse('2025-02-01T00:00:00Z')
      end

      let(:invalid_activities) do
        [
          { 'action' => 'broken', 'timestamp' => 'not-a-time' }
        ]
      end

      it 'falls back to current time for grouping and preserves raw timestamps' do
        allow(Time).to receive(:now).and_return(now_for_parse)
        result = reporter.format_timeline(invalid_activities, :day)
        expect(result.length).to eq(1)
        expect(result.first[:period]).to eq('2025-02-01')
        expect(result.first[:first_timestamp]).to eq('not-a-time')
        expect(result.first[:last_timestamp]).to eq('not-a-time')
      end
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 'abc',
        summary: { total_actions: 2 },
        timeline: []
      }
    end

    it 'returns pretty JSON data when no filepath is provided' do
      result = reporter.export_to_json(report)
      expect(result[:success]).to be true
      parsed = JSON.parse(result[:data])
      expect(parsed).to eq({
                             'user_id' => 'abc',
                             'summary' => { 'total_actions' => 2 },
                             'timeline' => []
                           })
    end

    it 'writes to a file when a filepath is provided and returns metadata' do
      require 'tmpdir'
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(report, path)
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(path)
        expected_json = JSON.pretty_generate(report)
        expect(result[:size]).to eq(expected_json.bytesize)
        written = File.read(path)
        expect(written).to eq(expected_json)
      end
    end

    it 'returns an error hash when writing fails' do
      allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      result = reporter.export_to_json(report, '/unwritable/path.json')
      expect(result[:success]).to be false
      expect(result[:error]).to eq('disk full')
    end
  end

  describe '#compare_users' do
    context 'when fewer than 2 users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with multiple users' do
      let(:uids) do
        %w[u1 u2 u3]
      end

      let(:acts_u1) do
        [{ 'action' => 'login', 'timestamp' => '2025-01-01T10:00:00Z' }]
      end

      let(:acts_u2) do
        [{ 'action' => 'view', 'timestamp' => '2025-01-02T11:00:00Z' },
         { 'action' => 'logout', 'timestamp' => '2025-01-02T12:00:00Z' }]
      end

      let(:acts_u3) do
        [{ 'action' => 'login', 'timestamp' => '2025-01-03T09:00:00Z' }]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return(acts_u1)
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return(acts_u2)
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return(acts_u3)

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({ total_actions: 5, unique_actions: 2,
                                                                                  action_counts: {}, first_activity: fixed_time.iso8601, last_activity: fixed_time.iso8601, most_frequent: 'login' })
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({ total_actions: 10, unique_actions: 3,
                                                                                  action_counts: {}, first_activity: fixed_time.iso8601, last_activity: fixed_time.iso8601, most_frequent: 'view' })
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return({ total_actions: 3, unique_actions: 1,
                                                                                  action_counts: {}, first_activity: fixed_time.iso8601, last_activity: fixed_time.iso8601, most_frequent: 'login' })

        allow(reporter).to receive(:fetch_user_score).with(acts_u1).and_return(70.0)
        allow(reporter).to receive(:fetch_user_score).with(acts_u2).and_return(85.0)
        allow(reporter).to receive(:fetch_user_score).with(acts_u3).and_return(60.0)
      end

      it 'returns comparisons sorted by engagement score with top user and average score' do
        result = reporter.compare_users(uids)
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[u2 u1 u3])
        expect(result[:comparisons].map { |c| c[:engagement_score] }).to eq([85.0, 70.0, 60.0])
        expect(result[:comparisons].map { |c| c[:total_actions] }).to eq([10, 5, 3])
        expect(result[:comparisons].map { |c| c[:most_frequent_action] }).to eq(%w[view login login])
        expect(result[:top_user]).to eq('u2')
        expect(result[:average_score]).to eq(((85.0 + 70.0 + 60.0) / 3.0).round(2))
      end
    end
  end
end
