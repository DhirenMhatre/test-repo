require 'spec_helper'
require 'json'
require 'tmpdir'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  describe '#generate_report' do
    let(:reporter) { described_class.new }
    let(:user_id) { 'user-123' }

    context 'when no activities exist' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report indicating no activities found' do
        result = reporter.generate_report(user_id)
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with activities and full data' do
      let(:activities) do
        [
          { 'timestamp' => '2023-08-01T10:15:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-08-01T10:35:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-08-01T11:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-08-01T11:45:00Z', 'action' => 'purchase' }
        ]
      end

      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 12,
          action_counts: { 'click' => 80, 'view' => 50, 'purchase' => 20 },
          first_activity: '2023-08-01T09:00:00Z',
          last_activity: '2023-08-02T18:00:00Z',
          most_frequent: 'click'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'sequence', 'description' => 'click->view', 'confidence' => 0.9 },
          { 'pattern_type' => 'burst', 'description' => 'morning activity', 'confidence' => 0.8 },
          { 'pattern_type' => 'cluster', 'description' => 'purchases after 3 views', 'confidence' => 0.7 }
        ]
      end

      let(:anomalies) { ['suspicious login', 'fraud attempt'] }
      let(:user_score) { 88.5 }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a rich report with summary, breakdown, patterns, anomalies, timeline and insights' do
        result = reporter.generate_report(user_id, group_by: :hour)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to be_a(String)

        expect(result[:summary][:total_actions]).to eq(150)
        expect(result[:summary][:unique_actions]).to eq(12)
        expect(result[:summary][:engagement_score]).to eq(88.5)
        expect(result[:summary][:first_activity]).to eq('2023-08-01T09:00:00Z')
        expect(result[:summary][:last_activity]).to eq('2023-08-02T18:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'click' => 80, 'view' => 50, 'purchase' => 20 })

        expect(result[:patterns]).to eq([
                                          { type: 'sequence', description: 'click->view', confidence: 0.9 },
                                          { type: 'burst', description: 'morning activity', confidence: 0.8 },
                                          { type: 'cluster', description: 'purchases after 3 views', confidence: 0.7 }
                                        ])

        expect(result[:anomalies]).to eq(anomalies)

        periods = result[:timeline].map { |e| e[:period] }
        expect(periods).to eq(['2023-08-01 10:00', '2023-08-01 11:00'])

        ten_bucket = result[:timeline].find { |e| e[:period] == '2023-08-01 10:00' }
        eleven_bucket = result[:timeline].find { |e| e[:period] == '2023-08-01 11:00' }

        expect(ten_bucket[:total_actions]).to eq(2)
        expect(ten_bucket[:actions]).to eq({ 'click' => 1, 'view' => 1 })
        expect(eleven_bucket[:total_actions]).to eq(2)
        expect(eleven_bucket[:actions]).to eq({ 'click' => 1, 'purchase' => 1 })

        expect(result[:insights]).to include(
          'Highly engaged user with strong activity patterns',
          'Diverse activity profile across multiple action types',
          'Clear behavioral patterns detected',
          '2 anomalous activities detected - review recommended',
          'Power user - high volume of activities'
        )
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) { described_class.new }

    context 'when activities are empty' do
      it 'returns an empty array' do
        result = reporter.format_timeline([])
        expect(result).to eq([])
      end
    end

    context 'when grouping by day' do
      let(:activities) do
        [
          { 'timestamp' => '2023-08-01T10:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2023-08-01T12:00:00Z', 'action' => 'b' },
          { 'timestamp' => '2023-08-02T09:00:00Z', 'action' => 'a' }
        ]
      end

      it 'aggregates by day with correct counts and sorted periods' do
        result = reporter.format_timeline(activities, :day)
        periods = result.map { |e| e[:period] }
        expect(periods).to eq(%w[2023-08-01 2023-08-02])

        day1 = result.find { |e| e[:period] == '2023-08-01' }
        day2 = result.find { |e| e[:period] == '2023-08-02' }
        expect(day1[:total_actions]).to eq(2)
        expect(day1[:actions]).to eq({ 'a' => 1, 'b' => 1 })
        expect(day2[:total_actions]).to eq(1)
        expect(day2[:actions]).to eq({ 'a' => 1 })
      end
    end

    context 'when grouping by hour' do
      let(:activities) do
        [
          { 'timestamp' => '2023-08-01T10:05:00Z', 'action' => 'x' },
          { 'timestamp' => '2023-08-01T10:30:00Z', 'action' => 'x' },
          { 'timestamp' => '2023-08-01T11:00:00Z', 'action' => 'y' }
        ]
      end

      it 'aggregates by hour' do
        result = reporter.format_timeline(activities, :hour)
        expect(result.map { |e| e[:period] }).to eq(['2023-08-01 10:00', '2023-08-01 11:00'])
        bucket = result.first
        expect(bucket[:total_actions]).to eq(2)
        expect(bucket[:actions]).to eq({ 'x' => 2 })
      end
    end

    context 'when grouping by week' do
      let(:activities) do
        [
          { 'timestamp' => '2023-08-02T10:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2023-08-09T10:00:00Z', 'action' => 'b' }
        ]
      end

      it 'aggregates by ISO week' do
        result = reporter.format_timeline(activities, :week)
        expect(result.map { |e| e[:period] }).to all(match(/\A\d{4}-W\d{2}\z/))
        expect(result.length).to eq(2)
      end
    end

    context 'when grouping by month' do
      let(:activities) do
        [
          { 'timestamp' => '2023-07-31T23:59:59Z', 'action' => 'end' },
          { 'timestamp' => '2023-08-01T00:00:01Z', 'action' => 'start' }
        ]
      end

      it 'aggregates by month' do
        result = reporter.format_timeline(activities, :month)
        expect(result.map { |e| e[:period] }).to eq(%w[2023-07 2023-08])
      end
    end

    context 'when group_by is unknown' do
      let(:activities) do
        [
          { 'timestamp' => '2023-08-01T10:00:00Z', 'action' => 'a' }
        ]
      end

      it 'falls back to day grouping' do
        result = reporter.format_timeline(activities, :unknown_group)
        expect(result.map { |e| e[:period] }).to eq(['2023-08-01'])
      end
    end

    context 'when an activity has an invalid timestamp' do
      let(:activities) do
        [
          { 'timestamp' => 'not-a-time', 'action' => 'bad' }
        ]
      end

      it 'uses the current time as fallback for grouping' do
        allow(Time).to receive(:now).and_return(Time.utc(2023, 1, 1, 12, 0, 0))
        result = reporter.format_timeline(activities, :day)
        expect(result.map { |e| e[:period] }).to eq(['2023-01-01'])
      end
    end
  end

  describe '#export_to_json' do
    let(:reporter) { described_class.new }
    let(:report_hash) do
      {
        user_id: 'u1',
        summary: { total_actions: 3 },
        timeline: []
      }
    end

    context 'when no filepath is provided' do
      it 'returns pretty JSON in data and success true' do
        result = reporter.export_to_json(report_hash)
        expect(result[:success]).to be true
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq('u1')
        expect(parsed['summary']['total_actions']).to eq(3)
      end
    end

    context 'when filepath is provided' do
      it 'writes the JSON to disk and returns metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report_hash, path)
          expect(result[:success]).to be true
          expect(result[:filepath]).to eq(path)
          expect(File).to exist(path)
          content = File.read(path)
          expect(content.bytesize).to eq(result[:size])
          expect(JSON.parse(content)['user_id']).to eq('u1')
        end
      end
    end

    context 'when writing the file raises an error' do
      it 'returns success false with error message' do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report_hash, path)
          expect(result[:success]).to be false
          expect(result[:error]).to eq('disk full')
        end
      end
    end
  end

  describe '#compare_users' do
    let(:reporter) { described_class.new }

    context 'when fewer than 2 users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users([])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
      end

      it 'returns an error for a single user' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
      end
    end

    context 'when comparing multiple users' do
      let(:user_ids) { %w[u1 u2 u3] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{
                                                                                   'timestamp' => '2023-08-01T10:00:00Z', 'action' => 'a'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{
                                                                                   'timestamp' => '2023-08-01T10:00:00Z', 'action' => 'b'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([])

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({ total_actions: 10, unique_actions: 2,
                                                                                  action_counts: { 'a' => 10 }, first_activity: 't1', last_activity: 't2', most_frequent: 'a' })
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({ total_actions: 50, unique_actions: 3,
                                                                                  action_counts: { 'b' => 50 }, first_activity: 't1', last_activity: 't2', most_frequent: 'b' })
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return({ total_actions: 20, unique_actions: 1,
                                                                                  action_counts: { 'c' => 20 }, first_activity: 't1', last_activity: 't2', most_frequent: 'c' })

        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2023-08-01T10:00:00Z',
                                                              'action' => 'a' }]).and_return(10.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2023-08-01T10:00:00Z',
                                                              'action' => 'b' }]).and_return(50.0)
        allow(reporter).to receive(:fetch_user_score).with([]).and_return(20.0)
      end

      it 'returns sorted comparisons by engagement score with top user and average score' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[u2 u3 u1])
        expect(result[:comparisons].map { |c| c[:engagement_score] }).to eq([50.0, 20.0, 10.0])
        expect(result[:comparisons].map { |c| c[:most_frequent_action] }).to eq(%w[b c a])
        expect(result[:top_user]).to eq('u2')
        expect(result[:average_score]).to eq(((50.0 + 20.0 + 10.0) / 3.0).round(2))
      end

      it 'invokes fetchers for each user' do
        reporter.compare_users(user_ids)
        user_ids.each do |uid|
          expect(reporter).to have_received(:fetch_user_activities).with(uid)
          expect(reporter).to have_received(:fetch_activity_stats).with(uid)
        end
      end
    end
  end
end
