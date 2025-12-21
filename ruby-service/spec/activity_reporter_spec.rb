require 'spec_helper'
require 'time'
require 'json'
require 'tmpdir'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new(go_service_url: 'http://go', python_service_url: 'http://py')
  end

  describe '#generate_report' do
    let(:fixed_time) { Time.parse('2025-01-02T12:34:56Z') }

    before do
      allow(Time).to receive(:now).and_return(fixed_time)
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('user-1').and_return([])
      end

      it 'returns an error report with message and generated_at timestamp' do
        result = reporter.generate_report('user-1')
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'when activities exist' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T10:00:00Z' },
          { 'action' => 'click', 'timestamp' => '2025-01-01T11:00:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 2,
          unique_actions: 2,
          action_counts: { 'login' => 1, 'click' => 1 },
          first_activity: '2025-01-01T10:00:00Z',
          last_activity: '2025-01-01T11:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'sequence', 'description' => 'A->B', 'confidence' => 0.9 }
        ]
      end

      let(:timeline) do
        [
          {
            period: '2025-01-01',
            total_actions: 2,
            actions: { 'login' => 1, 'click' => 1 },
            first_timestamp: '2025-01-01T10:00:00Z',
            last_timestamp: '2025-01-01T11:00:00Z'
          }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('user-1').and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with('user-1').and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(88.5)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(['outlier1'])
        allow(reporter).to receive(:format_timeline).with(activities, :day).and_return(timeline)
      end

      it 'builds a comprehensive report with summary, patterns, anomalies, timeline, and insights' do
        result = reporter.generate_report('user-1', group_by: :day)
        expect(result[:user_id]).to eq('user-1')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
        expect(result[:summary]).to include(
          total_actions: 2,
          unique_actions: 2,
          engagement_score: 88.5,
          first_activity: '2025-01-01T10:00:00Z',
          last_activity: '2025-01-01T11:00:00Z'
        )
        expect(result[:action_breakdown]).to eq({ 'login' => 1, 'click' => 1 })
        expect(result[:patterns]).to eq([{ type: 'sequence', description: 'A->B', confidence: 0.9 }])
        expect(result[:anomalies]).to eq(['outlier1'])
        expect(result[:timeline]).to eq(timeline)
        expect(result[:insights]).to be_an(Array)
        expect(result[:insights].join(' ')).to include('Highly engaged user')
        expect(result[:insights].join(' ')).to include('anomalous activities')
      end
    end

    context 'respects provided group_by option' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T10:00:00Z' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('user-2').and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with('user-2').and_return(
          {
            total_actions: 1,
            unique_actions: 1,
            action_counts: { 'login' => 1 },
            first_activity: '2025-01-01T10:00:00Z',
            last_activity: '2025-01-01T10:00:00Z',
            most_frequent: 'login'
          }
        )
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return([])
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(10.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([])
      end

      it 'passes the correct group_by to format_timeline' do
        expect(reporter).to receive(:format_timeline).with(activities, :hour).and_return([])
        reporter.generate_report('user-2', group_by: :hour)
      end
    end
  end

  describe '#format_timeline' do
    context 'when activities are empty' do
      it 'returns an empty array' do
        result = reporter.format_timeline([], :day)
        expect(result).to eq([])
      end
    end

    context 'groups by day and sorts periods ascending with correct counts' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-02T09:00:00Z' },
          { 'action' => 'click', 'timestamp' => '2025-01-01T10:00:00Z' },
          { 'action' => 'click', 'timestamp' => '2025-01-01T11:00:00Z' }
        ]
      end

      it 'produces per-day entries with action breakdown and first/last timestamps' do
        result = reporter.format_timeline(activities, :day)
        expect(result.size).to eq(2)
        expect(result[0][:period]).to eq('2025-01-01')
        expect(result[0][:total_actions]).to eq(2)
        expect(result[0][:actions]).to eq({ 'click' => 2 })
        expect(result[0][:first_timestamp]).to eq('2025-01-01T10:00:00Z')
        expect(result[0][:last_timestamp]).to eq('2025-01-01T11:00:00Z')

        expect(result[1][:period]).to eq('2025-01-02')
        expect(result[1][:total_actions]).to eq(1)
        expect(result[1][:actions]).to eq({ 'login' => 1 })
        expect(result[1][:first_timestamp]).to eq('2025-01-02T09:00:00Z')
        expect(result[1][:last_timestamp]).to eq('2025-01-02T09:00:00Z')
      end
    end

    context 'groups by month' do
      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-03-10T09:00:00Z' },
          { 'action' => 'click', 'timestamp' => '2025-03-11T10:00:00Z' }
        ]
      end

      it 'uses YYYY-MM period format' do
        result = reporter.format_timeline(activities, :month)
        expect(result.size).to eq(1)
        expect(result.first[:period]).to eq('2025-03')
        expect(result.first[:actions]).to eq({ 'login' => 1, 'click' => 1 })
      end
    end

    context 'handles invalid timestamps by using current time' do
      let(:fixed_time) { Time.parse('2025-04-05T12:00:00Z') }

      before do
        allow(Time).to receive(:now).and_return(fixed_time)
      end

      it 'falls back to Time.now for grouping' do
        activities = [{ 'action' => 'login', 'timestamp' => 'invalid' }]
        result = reporter.format_timeline(activities, :day)
        expect(result.size).to eq(1)
        expect(result.first[:period]).to eq(fixed_time.strftime('%Y-%m-%d'))
        expect(result.first[:actions]).to eq({ 'login' => 1 })
      end
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 'u1',
        summary: { total_actions: 3 }
      }
    end

    context 'when no filepath is provided' do
      it 'returns success with JSON data string' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be true
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq('u1')
        expect(parsed['summary']['total_actions']).to eq(3)
      end
    end

    context 'when a filepath is provided' do
      it 'writes the file and returns success with filepath and size' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to be true
          expect(result[:filepath]).to eq(path)
          expect(File).to exist(path)
          content = File.read(path)
          expect(content).to eq(JSON.pretty_generate(report))
          expect(result[:size]).to eq(content.bytesize)
        end
      end
    end

    context 'when writing fails' do
      it 'returns a failure with error message' do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        result = reporter.export_to_json(report, '/tmp/nowhere.json')
        expect(result[:success]).to be false
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    let(:fixed_time) { Time.parse('2025-01-02T00:00:00Z') }

    before do
      allow(Time).to receive(:now).and_return(fixed_time)
    end

    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with multiple users' do
      let(:user_ids) { ['a', 'b', 'c'] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with('a').and_return([{ 'action' => 'x', 'timestamp' => '2025-01-01T00:00:00Z' }])
        allow(reporter).to receive(:fetch_user_activities).with('b').and_return([{ 'action' => 'y', 'timestamp' => '2025-01-01T00:01:00Z' }])
        allow(reporter).to receive(:fetch_user_activities).with('c').and_return([{ 'action' => 'z', 'timestamp' => '2025-01-01T00:02:00Z' }])

        allow(reporter).to receive(:fetch_activity_stats).with('a').and_return(
          {
            total_actions: 10,
            unique_actions: 3,
            action_counts: { 'x' => 10 },
            first_activity: '2025-01-01T00:00:00Z',
            last_activity: '2025-01-01T01:00:00Z',
            most_frequent: 'x'
          }
        )
        allow(reporter).to receive(:fetch_activity_stats).with('b').and_return(
          {
            total_actions: 20,
            unique_actions: 4,
            action_counts: { 'y' => 20 },
            first_activity: '2025-01-01T00:01:00Z',
            last_activity: '2025-01-01T02:00:00Z',
            most_frequent: 'y'
          }
        )
        allow(reporter).to receive(:fetch_activity_stats).with('c').and_return(
          {
            total_actions: 15,
            unique_actions: 2,
            action_counts: { 'z' => 15 },
            first_activity: '2025-01-01T00:02:00Z',
            last_activity: '2025-01-01T03:00:00Z',
            most_frequent: 'z'
          }
        )

        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'x', 'timestamp' => '2025-01-01T00:00:00Z' }]).and_return(30.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'y', 'timestamp' => '2025-01-01T00:01:00Z' }]).and_return(80.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'action' => 'z', 'timestamp' => '2025-01-01T00:02:00Z' }]).and_return(50.0)
      end

      it 'returns sorted comparisons by engagement score and computes top_user and average_score' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(['b', 'c', 'a'])
        expect(result[:comparisons].first[:engagement_score]).to eq(80.0)
        expect(result[:comparisons].first[:most_frequent_action]).to eq('y')
        expect(result[:top_user]).to eq('b')
        expect(result[:average_score]).to eq(((30.0 + 80.0 + 50.0) / 3.0).round(2))
      end
    end
  end
end
