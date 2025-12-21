require 'spec_helper'
require 'json'
require 'time'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new(
      go_service_url: 'http://go.test:8080',
      python_service_url: 'http://py.test:8081'
    )
  end

  describe '#generate_report' do
    let(:user_id) { 'user-123' }
    let(:now) { Time.utc(2023, 1, 2, 3, 4, 5) }

    before do
      allow(Time).to receive(:now).and_return(now)
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report with appropriate message' do
        result = reporter.generate_report(user_id)
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(now.iso8601)
      end
    end

    context 'when activities are present with moderate engagement' do
      let(:activities) do
        [
          { 'action' => 'click', 'timestamp' => '2023-01-01T10:00:00Z' },
          { 'action' => 'view',  'timestamp' => '2023-01-01T11:00:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 2,
          unique_actions: 2,
          action_counts: { 'click' => 1, 'view' => 1 },
          first_activity: '2023-01-01T10:00:00Z',
          last_activity: '2023-01-01T11:00:00Z',
          most_frequent: 'click'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'sequence', 'description' => 'click then view', 'confidence' => 0.8 },
          { 'pattern_type' => 'daily', 'description' => 'morning usage', 'confidence' => 0.6 }
        ]
      end

      let(:user_score) { 55.0 }
      let(:anomalies) { [] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a comprehensive report with hourly timeline and formatted patterns' do
        result = reporter.generate_report(user_id, group_by: :hour)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(now.iso8601)

        expect(result[:summary][:total_actions]).to eq(2)
        expect(result[:summary][:unique_actions]).to eq(2)
        expect(result[:summary][:engagement_score]).to eq(55.0)
        expect(result[:summary][:first_activity]).to eq('2023-01-01T10:00:00Z')
        expect(result[:summary][:last_activity]).to eq('2023-01-01T11:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'click' => 1, 'view' => 1 })

        expect(result[:patterns]).to contain_exactly(
          { type: 'sequence', description: 'click then view', confidence: 0.8 },
          { type: 'daily', description: 'morning usage', confidence: 0.6 }
        )

        expect(result[:anomalies]).to eq([])

        expect(result[:timeline].size).to eq(2)
        expect(result[:timeline][0][:period]).to eq('2023-01-01 10:00')
        expect(result[:timeline][0][:total_actions]).to eq(1)
        expect(result[:timeline][0][:actions]).to eq({ 'click' => 1 })
        expect(result[:timeline][0][:first_timestamp]).to eq('2023-01-01T10:00:00Z')
        expect(result[:timeline][0][:last_timestamp]).to eq('2023-01-01T10:00:00Z')

        expect(result[:timeline][1][:period]).to eq('2023-01-01 11:00')
        expect(result[:timeline][1][:total_actions]).to eq(1)
        expect(result[:timeline][1][:actions]).to eq({ 'view' => 1 })
        expect(result[:timeline][1][:first_timestamp]).to eq('2023-01-01T11:00:00Z')
        expect(result[:timeline][1][:last_timestamp]).to eq('2023-01-01T11:00:00Z')

        expect(result[:insights]).to include('Moderately engaged user with regular activity')
        expect(result[:insights].join(' ')).not_to include('Power user - high volume of activities')
      end
    end

    context 'when conditions trigger all additional insights' do
      let(:activities) do
        [
          { 'action' => 'a1', 'timestamp' => '2023-06-15T09:00:00Z' },
          { 'action' => 'a2', 'timestamp' => '2023-06-15T10:00:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 101,
          unique_actions: 12,
          action_counts: { 'a1' => 50, 'a2' => 51 },
          first_activity: '2023-06-15T09:00:00Z',
          last_activity: '2023-06-15T10:00:00Z',
          most_frequent: 'a2'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'pattern1', 'description' => 'p1', 'confidence' => 0.9 },
          { 'pattern_type' => 'pattern2', 'description' => 'p2', 'confidence' => 0.8 },
          { 'pattern_type' => 'pattern3', 'description' => 'p3', 'confidence' => 0.7 }
        ]
      end

      let(:user_score) { 82.3 }
      let(:anomalies) do
        [
          { 'action' => 'weird', 'timestamp' => '2023-06-15T09:30:00Z' },
          { 'action' => 'odd', 'timestamp' => '2023-06-15T09:45:00Z' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'includes all relevant insight messages' do
        result = reporter.generate_report(user_id)

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('2 anomalous activities detected - review recommended')
        expect(result[:insights]).to include('Power user - high volume of activities')
        expect(result[:insights].join(' ')).not_to include('Moderately engaged user with regular activity')
        expect(result[:insights].join(' ')).not_to include('Low engagement - consider re-engagement strategies')
      end
    end

    context 'when group_by option is invalid' do
      let(:activities) do
        [
          { 'action' => 'x', 'timestamp' => '2023-02-01T10:00:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 1,
          unique_actions: 1,
          action_counts: { 'x' => 1 },
          first_activity: '2023-02-01T10:00:00Z',
          last_activity: '2023-02-01T10:00:00Z',
          most_frequent: 'x'
        }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return([])
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(10.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([])
      end

      it 'defaults to day grouping' do
        result = reporter.generate_report(user_id, group_by: :unknown)
        expect(result[:timeline].size).to eq(1)
        expect(result[:timeline][0][:period]).to eq('2023-02-01')
      end
    end
  end

  describe '#format_timeline' do
    let(:now) { Time.utc(2023, 3, 4, 5, 6, 7) }

    before do
      allow(Time).to receive(:now).and_return(now)
    end

    it 'returns empty array when no activities' do
      expect(reporter.format_timeline([])).to eq([])
    end

    it 'groups by hour' do
      activities = [
        { 'action' => 'a', 'timestamp' => '2023-06-15T09:15:00Z' },
        { 'action' => 'a', 'timestamp' => '2023-06-15T09:45:00Z' },
        { 'action' => 'b', 'timestamp' => '2023-06-15T10:05:00Z' }
      ]
      timeline = reporter.format_timeline(activities, :hour)
      expect(timeline.map { |t| t[:period] }).to eq(['2023-06-15 09:00', '2023-06-15 10:00'])
      expect(timeline[0][:total_actions]).to eq(2)
      expect(timeline[0][:actions]).to eq({ 'a' => 2 })
      expect(timeline[1][:total_actions]).to eq(1)
      expect(timeline[1][:actions]).to eq({ 'b' => 1 })
    end

    it 'groups by day' do
      activities = [
        { 'action' => 'a', 'timestamp' => '2023-06-15T09:15:00Z' },
        { 'action' => 'b', 'timestamp' => '2023-06-16T10:05:00Z' }
      ]
      timeline = reporter.format_timeline(activities, :day)
      expect(timeline.map { |t| t[:period] }).to eq(%w[2023-06-15 2023-06-16])
      expect(timeline[0][:actions]).to eq({ 'a' => 1 })
      expect(timeline[1][:actions]).to eq({ 'b' => 1 })
    end

    it 'groups by week' do
      activities = [
        { 'action' => 'a', 'timestamp' => '2023-06-15T09:15:00Z' },
        { 'action' => 'b', 'timestamp' => '2023-06-17T10:05:00Z' }
      ]
      expected_week1 = Time.parse('2023-06-15T09:15:00Z').strftime('%Y-W%V')
      expected_week2 = Time.parse('2023-06-17T10:05:00Z').strftime('%Y-W%V')
      timeline = reporter.format_timeline(activities, :week)
      expect(timeline.map { |t| t[:period] }).to eq([expected_week1, expected_week2].sort.uniq)
    end

    it 'groups by month' do
      activities = [
        { 'action' => 'a', 'timestamp' => '2023-05-31T23:59:00Z' },
        { 'action' => 'b', 'timestamp' => '2023-06-01T00:01:00Z' }
      ]
      timeline = reporter.format_timeline(activities, :month)
      expect(timeline.map { |t| t[:period] }).to eq(%w[2023-05 2023-06])
    end

    it 'defaults to day grouping when unknown group_by is given' do
      activities = [
        { 'action' => 'a', 'timestamp' => '2023-06-15T09:15:00Z' }
      ]
      timeline = reporter.format_timeline(activities, :unknown)
      expect(timeline.map { |t| t[:period] }).to eq(['2023-06-15'])
    end

    it 'handles invalid timestamps by using current time bucket' do
      activities = [
        { 'action' => 'oops', 'timestamp' => 'not-a-time' }
      ]
      timeline = reporter.format_timeline(activities, :day)
      expect(timeline.size).to eq(1)
      expect(timeline[0][:period]).to eq(now.strftime('%Y-%m-%d'))
      expect(timeline[0][:total_actions]).to eq(1)
      expect(timeline[0][:actions]).to eq({ 'oops' => 1 })
    end
  end

  describe '#export_to_json' do
    let(:report_hash) do
      {
        user_id: 'u1',
        summary: { total_actions: 3 },
        timeline: []
      }
    end

    it 'returns pretty JSON data when no filepath is provided' do
      result = reporter.export_to_json(report_hash)
      expect(result[:success]).to be true
      expect(result[:data]).to be_a(String)
      parsed = JSON.parse(result[:data])
      expect(parsed['user_id']).to eq('u1')
      expect(parsed['summary']['total_actions']).to eq(3)
    end

    it 'writes JSON to the given filepath and returns metadata' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(report_hash, path)
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(path)
        expect(result[:size]).to eq(JSON.pretty_generate(report_hash).bytesize)
        file_content = File.read(path)
        expect(JSON.parse(file_content)['user_id']).to eq('u1')
      end
    end

    it 'returns an error hash when writing fails' do
      allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      result = reporter.export_to_json(report_hash, '/tmp/will-not-work.json')
      expect(result[:success]).to be false
      expect(result[:error]).to eq('disk full')
    end
  end

  describe '#compare_users' do
    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with two or more users' do
      let(:user_ids) { %w[u1 u2 u3] }

      before do
        # Activities can be minimal as they are only used to compute score via fetch_user_score stub
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{ 'action' => 'a',
                                                                                    'timestamp' => '2023-01-01T00:00:00Z' }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{ 'action' => 'b',
                                                                                    'timestamp' => '2023-01-02T00:00:00Z' }])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([{ 'action' => 'c',
                                                                                    'timestamp' => '2023-01-03T00:00:00Z' }])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return(
          { total_actions: 10, unique_actions: 5, action_counts: { 'a' => 10 }, first_activity: 't1',
            last_activity: 't1', most_frequent: 'a' }
        )
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return(
          { total_actions: 20, unique_actions: 3, action_counts: { 'b' => 20 }, first_activity: 't2',
            last_activity: 't2', most_frequent: 'b' }
        )
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return(
          { total_actions: 5, unique_actions: 2, action_counts: { 'c' => 5 }, first_activity: 't3',
            last_activity: 't3', most_frequent: 'c' }
        )

        allow(reporter).to receive(:fetch_user_score).with(array_including).and_return(0.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'a',
                                                              'timestamp' => '2023-01-01T00:00:00Z' }]).and_return(70.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'b',
                                                              'timestamp' => '2023-01-02T00:00:00Z' }]).and_return(85.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'c',
                                                              'timestamp' => '2023-01-03T00:00:00Z' }]).and_return(65.0)
      end

      it 'returns sorted comparisons by engagement score, top user, and average score' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[u2 u1 u3])
        expect(result[:comparisons][0][:engagement_score]).to eq(85.0)
        expect(result[:comparisons][0][:most_frequent_action]).to eq('b')
        expect(result[:top_user]).to eq('u2')
        expect(result[:average_score]).to eq(((85.0 + 70.0 + 65.0) / 3.0).round(2))
      end
    end
  end
end
