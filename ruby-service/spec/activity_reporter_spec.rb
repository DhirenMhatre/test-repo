require 'spec_helper'
require 'json'
require 'time'
require 'tmpdir'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new
  end

  describe '#initialize' do
    context 'with defaults' do
      it 'sets default service urls' do
        expect(reporter.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
        expect(reporter.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
      end
    end

    context 'with custom urls' do
      let(:custom_reporter) do
        described_class.new(go_service_url: 'http://go.example', python_service_url: 'http://py.example')
      end

      it 'sets custom service urls' do
        expect(custom_reporter.instance_variable_get(:@go_service_url)).to eq('http://go.example')
        expect(custom_reporter.instance_variable_get(:@python_service_url)).to eq('http://py.example')
      end
    end
  end

  describe '#generate_report' do
    context 'when no activities found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('user-1').and_return([])
      end

      it 'returns an error report with proper message' do
        result = reporter.generate_report('user-1')
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to be_a(String)
      end

      it 'does not fetch stats, patterns, score, or anomalies' do
        allow(reporter).to receive(:fetch_activity_stats)
        allow(reporter).to receive(:fetch_activity_patterns)
        allow(reporter).to receive(:fetch_user_score)
        allow(reporter).to receive(:fetch_anomalies)

        reporter.generate_report('user-1')

        expect(reporter).not_to have_received(:fetch_activity_stats)
        expect(reporter).not_to have_received(:fetch_activity_patterns)
        expect(reporter).not_to have_received(:fetch_user_score)
        expect(reporter).not_to have_received(:fetch_anomalies)
      end
    end

    context 'with activities and options' do
      let(:activities) do
        [
          { 'timestamp' => '2023-01-01T08:30:00Z', 'action' => 'login' },
          { 'timestamp' => '2023-01-01T09:30:00Z', 'action' => 'click' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('user-2').and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with('user-2').and_return(
          {
            total_actions: 2,
            unique_actions: 2,
            action_counts: { 'login' => 1, 'click' => 1 },
            first_activity: '2023-01-01T08:30:00Z',
            last_activity: '2023-01-01T09:30:00Z',
            most_frequent: 'login'
          }
        )
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(
          [
            { 'pattern_type' => 'burst', 'description' => 'morning activity', 'confidence' => 0.9 }
          ]
        )
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(60.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([])

        expect(reporter).to receive(:format_timeline).with(activities, :hour).and_return(
          [
            {
              period: '2023-01-01 08:00',
              total_actions: 1,
              actions: { 'login' => 1 },
              first_timestamp: '2023-01-01T08:30:00Z',
              last_timestamp: '2023-01-01T08:30:00Z'
            }
          ]
        )
      end

      it 'builds a comprehensive report with mapped patterns and insights' do
        result = reporter.generate_report('user-2', group_by: :hour)
        expect(result[:user_id]).to eq('user-2')
        expect(result[:generated_at]).to be_a(String)
        expect(result[:summary][:total_actions]).to eq(2)
        expect(result[:summary][:unique_actions]).to eq(2)
        expect(result[:summary][:engagement_score]).to eq(60.0)
        expect(result[:action_breakdown]).to eq({ 'login' => 1, 'click' => 1 })
        expect(result[:patterns]).to eq([{ type: 'burst', description: 'morning activity', confidence: 0.9 }])
        expect(result[:anomalies]).to eq([])
        expect(result[:timeline]).to be_a(Array)
        expect(result[:insights]).to include('Moderately engaged user with regular activity')
      end
    end

    context 'insights reflect multiple conditions' do
      let(:activities) do
        [
          { 'timestamp' => '2023-01-01T00:00:00Z', 'action' => 'a' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).and_return(
          {
            total_actions: 150,
            unique_actions: 11,
            action_counts: { 'a' => 150 },
            first_activity: '2023-01-01T00:00:00Z',
            last_activity: '2023-01-02T00:00:00Z',
            most_frequent: 'a'
          }
        )
        allow(reporter).to receive(:fetch_activity_patterns).and_return(
          [
            { 'pattern_type' => 'p1', 'description' => 'd1', 'confidence' => 0.5 },
            { 'pattern_type' => 'p2', 'description' => 'd2', 'confidence' => 0.7 },
            { 'pattern_type' => 'p3', 'description' => 'd3', 'confidence' => 0.8 }
          ]
        )
        allow(reporter).to receive(:fetch_user_score).and_return(80.0)
        allow(reporter).to receive(:fetch_anomalies).and_return([{ 'id' => 1 }, { 'id' => 2 }])
        allow(reporter).to receive(:format_timeline).and_return([])
      end

      it 'includes high-engagement, diversity, patterns, anomalies, and power user insights' do
        result = reporter.generate_report('user-high')
        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('2 anomalous activities detected - review recommended')
        expect(result[:insights]).to include('Power user - high volume of activities')
      end
    end
  end

  describe '#format_timeline' do
    it 'returns empty array when no activities' do
      expect(reporter.format_timeline([])).to eq([])
    end

    it 'groups by day with correct counts and order' do
      activities = [
        { 'timestamp' => '2023-01-02T10:00:00Z', 'action' => 'login' },
        { 'timestamp' => '2023-01-01T10:00:00Z', 'action' => 'login' },
        { 'timestamp' => '2023-01-01T11:00:00Z', 'action' => 'click' }
      ]

      result = reporter.format_timeline(activities, :day)
      periods = result.map do |e|
        e[:period]
      end
      expect(periods).to eq(%w[2023-01-01 2023-01-02])

      jan1 = result.find do |e|
        e[:period] == '2023-01-01'
      end
      expect(jan1[:total_actions]).to eq(2)
      expect(jan1[:actions]).to eq({ 'login' => 1, 'click' => 1 })
      expect(jan1[:first_timestamp]).to eq('2023-01-01T10:00:00Z')
      expect(jan1[:last_timestamp]).to eq('2023-01-01T11:00:00Z')
    end

    it 'groups by hour' do
      activities = [
        { 'timestamp' => '2023-01-01T10:15:00Z', 'action' => 'a' },
        { 'timestamp' => '2023-01-01T10:45:00Z', 'action' => 'a' },
        { 'timestamp' => '2023-01-01T11:00:00Z', 'action' => 'b' }
      ]

      result = reporter.format_timeline(activities, :hour)
      periods = result.map do |e|
        e[:period]
      end
      expect(periods).to eq(['2023-01-01 10:00', '2023-01-01 11:00'])

      hour10 = result.find do |e|
        e[:period] == '2023-01-01 10:00'
      end
      expect(hour10[:total_actions]).to eq(2)
      expect(hour10[:actions]).to eq({ 'a' => 2 })
    end

    it 'groups by week using ISO week number' do
      activities = [
        { 'timestamp' => '2023-01-09T09:00:00Z', 'action' => 'a' },
        { 'timestamp' => '2023-01-10T10:00:00Z', 'action' => 'b' }
      ]

      result = reporter.format_timeline(activities, :week)
      expect(result.length).to eq(1)
      expect(result.first[:period]).to eq('2023-W02')
      expect(result.first[:total_actions]).to eq(2)
    end

    it 'groups by month' do
      activities = [
        { 'timestamp' => '2023-02-01T00:00:00Z', 'action' => 'x' },
        { 'timestamp' => '2023-02-15T00:00:00Z', 'action' => 'y' }
      ]

      result = reporter.format_timeline(activities, :month)
      expect(result.first[:period]).to eq('2023-02')
      expect(result.first[:total_actions]).to eq(2)
    end

    it 'falls back to day group when unknown group_by is provided' do
      activities = [
        { 'timestamp' => '2023-03-01T01:00:00Z', 'action' => 'x' },
        { 'timestamp' => '2023-03-01T02:00:00Z', 'action' => 'y' }
      ]

      result = reporter.format_timeline(activities, :unknown)
      expect(result.first[:period]).to eq('2023-03-01')
    end

    it 'handles invalid timestamps by grouping with current date' do
      fixed_now = Time.utc(2023, 5, 6, 12, 0, 0)
      allow(Time).to receive(:now).and_return(fixed_now)

      activities = [
        { 'timestamp' => 'not-a-time', 'action' => 'x' }
      ]

      result = reporter.format_timeline(activities, :day)
      expect(result.first[:period]).to eq('2023-05-06')
      expect(result.first[:actions]).to eq({ 'x' => 1 })
      expect(result.first[:first_timestamp]).to eq('not-a-time')
      expect(result.first[:last_timestamp]).to eq('not-a-time')
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 'u1',
        summary: { total_actions: 1, unique_actions: 1, engagement_score: 10.0 }
      }
    end

    context 'when filepath is not provided' do
      it 'returns JSON data string' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to eq(true)
        expect(result[:data]).to be_a(String)
        parsed = JSON.parse(result[:data])
        expect(parsed['user_id']).to eq('u1')
        expect(parsed['summary']['total_actions']).to eq(1)
      end
    end

    context 'when filepath is provided' do
      it 'writes to file and returns metadata' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'report.json')
          result = reporter.export_to_json(report, path)
          expect(result[:success]).to eq(true)
          expect(result[:filepath]).to eq(path)
          expect(File.exist?(path)).to eq(true)

          content = File.read(path)
          parsed = JSON.parse(content)
          expect(parsed['user_id']).to eq('u1')
          expect(result[:size]).to eq(content.bytesize)
        end
      end

      it 'handles write errors gracefully' do
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        result = reporter.export_to_json(report, '/tmp/fail.json')
        expect(result[:success]).to eq(false)
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    context 'when less than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with multiple users' do
      let(:u1_activities) do
        [{ 'timestamp' => '2023-01-01T00:00:00Z', 'action' => 'a' }]
      end
      let(:u2_activities) do
        [{ 'timestamp' => '2023-01-02T00:00:00Z', 'action' => 'b' },
         { 'timestamp' => '2023-01-02T01:00:00Z', 'action' => 'b' }]
      end
      let(:u3_activities) do
        []
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return(u1_activities)
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return(u2_activities)
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return(u3_activities)

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return(
          { total_actions: 1, unique_actions: 1, action_counts: { 'a' => 1 }, first_activity: '2023-01-01T00:00:00Z',
            last_activity: '2023-01-01T00:00:00Z', most_frequent: 'a' }
        )
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return(
          { total_actions: 2, unique_actions: 1, action_counts: { 'b' => 2 }, first_activity: '2023-01-02T00:00:00Z',
            last_activity: '2023-01-02T01:00:00Z', most_frequent: 'b' }
        )
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return(
          { total_actions: 0, unique_actions: 0, action_counts: {}, first_activity: Time.now.iso8601,
            last_activity: Time.now.iso8601, most_frequent: 'unknown' }
        )

        expect(reporter).to receive(:fetch_user_score).with(u1_activities).and_return(55.5)
        expect(reporter).to receive(:fetch_user_score).with(u2_activities).and_return(80.25)
        expect(reporter).to receive(:fetch_user_score).with(u3_activities).and_return(0.0)
      end

      it 'returns sorted comparisons by engagement score and computes average' do
        result = reporter.compare_users(%w[u1 u2 u3])
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map do |c|
          c[:user_id]
        end).to eq(%w[u2 u1 u3])
        expect(result[:top_user]).to eq('u2')
        expect(result[:average_score]).to eq(((80.25 + 55.5 + 0.0) / 3.0).round(2))
        u2_comp = result[:comparisons].find do |c|
          c[:user_id] == 'u2'
        end
        expect(u2_comp[:total_actions]).to eq(2)
        expect(u2_comp[:most_frequent_action]).to eq('b')
      end
    end
  end
end
