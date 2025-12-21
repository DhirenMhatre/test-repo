require 'spec_helper'
require 'time'
require 'json'
require 'tmpdir'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new
  end

  describe '#initialize' do
    it 'creates an instance without error' do
      expect do
        described_class.new
      end.not_to raise_error
    end

    it 'allows custom service URLs' do
      instance = described_class.new(go_service_url: 'http://go', python_service_url: 'http://py')
      expect(instance).to be_a(described_class)
    end
  end

  describe '#generate_report' do
    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('user-1').and_return([])
      end

      it 'returns an error report' do
        fixed_time = Time.parse('2024-01-01T00:00:00Z')
        allow(Time).to receive(:now).and_return(fixed_time)
        result = reporter.generate_report('user-1')
        expect(result[:error]).to be(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'when activities exist' do
      let(:activities) do
        [
          { 'timestamp' => '2024-02-01T10:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2024-02-01T11:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2024-02-02T12:00:00Z', 'action' => 'click' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('user-1').and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with('user-1').and_return(
          {
            total_actions: 150,
            unique_actions: 12,
            action_counts: { 'click' => 100, 'view' => 50 },
            first_activity: '2024-02-01T10:00:00Z',
            last_activity: '2024-02-02T12:00:00Z',
            most_frequent: 'click'
          }
        )
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(85.5)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(
          [
            { 'pattern_type' => 'burst', 'description' => 'Morning spikes', 'confidence' => 0.92 },
            { 'pattern_type' => 'repeat', 'description' => 'Daily login', 'confidence' => 0.88 },
            { 'pattern_type' => 'sequence', 'description' => 'Click then view', 'confidence' => 0.75 }
          ]
        )
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(
          [
            { 'timestamp' => '2024-02-01T03:00:00Z', 'action' => 'delete' },
            { 'timestamp' => '2024-02-02T23:00:00Z', 'action' => 'export' }
          ]
        )
        allow(reporter).to receive(:format_timeline).and_return([{ period: '2024-02-01', total_actions: 2 }])
      end

      it 'builds a rich report with summary, breakdown, patterns, anomalies, timeline and insights' do
        fixed_time = Time.parse('2024-02-03T00:00:00Z')
        allow(Time).to receive(:now).and_return(fixed_time)
        report = reporter.generate_report('user-1')

        expect(report[:user_id]).to eq('user-1')
        expect(report[:generated_at]).to eq(fixed_time.iso8601)

        expect(report[:summary][:total_actions]).to eq(150)
        expect(report[:summary][:unique_actions]).to eq(12)
        expect(report[:summary][:engagement_score]).to eq(85.5)
        expect(report[:summary][:first_activity]).to eq('2024-02-01T10:00:00Z')
        expect(report[:summary][:last_activity]).to eq('2024-02-02T12:00:00Z')

        expect(report[:action_breakdown]).to eq({ 'click' => 100, 'view' => 50 })

        expect(report[:patterns]).to eq(
          [
            { type: 'burst', description: 'Morning spikes', confidence: 0.92 },
            { type: 'repeat', description: 'Daily login', confidence: 0.88 },
            { type: 'sequence', description: 'Click then view', confidence: 0.75 }
          ]
        )

        expect(report[:anomalies].length).to eq(2)
        expect(report[:timeline]).to eq([{ period: '2024-02-01', total_actions: 2 }])

        expect(report[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(report[:insights]).to include('Diverse activity profile across multiple action types')
        expect(report[:insights]).to include('Clear behavioral patterns detected')
        expect(report[:insights]).to include('2 anomalous activities detected - review recommended')
        expect(report[:insights]).to include('Power user - high volume of activities')
      end

      it 'passes group_by option to format_timeline' do
        expect(reporter).to receive(:format_timeline).with(activities, :month).and_return([])
        reporter.generate_report('user-1', group_by: :month)
      end
    end
  end

  describe '#format_timeline' do
    let(:base_activities) do
      [
        { 'timestamp' => '2024-03-01T10:15:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-03-01T10:45:00Z', 'action' => 'view' },
        { 'timestamp' => '2024-03-01T11:05:00Z', 'action' => 'click' },
        { 'timestamp' => '2024-03-02T00:05:00Z', 'action' => 'purchase' }
      ]
    end

    it 'returns empty array when activities is empty' do
      expect(reporter.format_timeline([], :day)).to eq([])
    end

    it 'groups by hour when group_by is :hour' do
      result = reporter.format_timeline(base_activities, :hour)
      periods = result.map do |r|
        r[:period]
      end
      expect(periods).to include('2024-03-01 10:00')
      expect(periods).to include('2024-03-01 11:00')
      expect(periods).to include('2024-03-02 00:00')
      first_hour = result.find do |r|
        r[:period] == '2024-03-01 10:00'
      end
      expect(first_hour[:total_actions]).to eq(2)
      expect(first_hour[:actions]).to eq({ 'click' => 1, 'view' => 1 })
      expect(first_hour[:first_timestamp]).to eq('2024-03-01T10:15:00Z')
      expect(first_hour[:last_timestamp]).to eq('2024-03-01T10:45:00Z')
    end

    it 'groups by day by default' do
      result = reporter.format_timeline(base_activities)
      day = result.find do |r|
        r[:period] == '2024-03-01'
      end
      expect(day[:total_actions]).to eq(3)
      expect(day[:actions]).to eq({ 'click' => 2, 'view' => 1 })
    end

    it 'groups by week when group_by is :week' do
      sample_ts = '2024-01-02T10:00:00Z'
      acts = [
        { 'timestamp' => sample_ts, 'action' => 'login' },
        { 'timestamp' => '2024-01-03T10:00:00Z', 'action' => 'logout' }
      ]
      expected_period = Time.parse(sample_ts).strftime('%Y-W%V')
      result = reporter.format_timeline(acts, :week)
      expect(result.first[:period]).to eq(expected_period)
      expect(result.first[:total_actions]).to eq(2)
    end

    it 'groups by month when group_by is :month' do
      acts = [
        { 'timestamp' => '2024-05-10T09:00:00Z', 'action' => 'a' },
        { 'timestamp' => '2024-05-11T10:00:00Z', 'action' => 'b' },
        { 'timestamp' => '2024-06-01T00:00:00Z', 'action' => 'c' }
      ]
      result = reporter.format_timeline(acts, :month)
      may = result.find do |r|
        r[:period] == '2024-05'
      end
      june = result.find do |r|
        r[:period] == '2024-06'
      end
      expect(may[:total_actions]).to eq(2)
      expect(june[:total_actions]).to eq(1)
    end

    it 'falls back to day grouping for unknown group_by values' do
      acts = [
        { 'timestamp' => '2024-07-01T09:00:00Z', 'action' => 'x' },
        { 'timestamp' => '2024-07-01T10:00:00Z', 'action' => 'y' }
      ]
      result = reporter.format_timeline(acts, :unknown)
      expect(result.first[:period]).to eq('2024-07-01')
    end

    it 'handles invalid timestamps by using current time' do
      fixed_time = Time.parse('2024-08-08T08:08:08Z')
      allow(Time).to receive(:now).and_return(fixed_time)
      acts = [
        { 'timestamp' => 'INVALID', 'action' => 'x' }
      ]
      result = reporter.format_timeline(acts, :day)
      expect(result.first[:period]).to eq(fixed_time.strftime('%Y-%m-%d'))
      expect(result.first[:total_actions]).to eq(1)
    end

    it 'sorts timeline entries by period ascending' do
      acts = [
        { 'timestamp' => '2024-04-02T00:00:00Z', 'action' => 'a' },
        { 'timestamp' => '2024-04-01T00:00:00Z', 'action' => 'b' }
      ]
      result = reporter.format_timeline(acts, :day)
      expect(result.map do |r|
        r[:period]
      end).to eq(['2024-04-01', '2024-04-02'])
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

    it 'returns JSON string when no filepath is provided' do
      result = reporter.export_to_json(report_hash)
      expect(result[:success]).to be(true)
      parsed = JSON.parse(result[:data])
      expect(parsed['user_id']).to eq('u1')
      expect(parsed['summary']['total_actions']).to eq(3)
    end

    it 'writes JSON to a file when filepath is provided' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(report_hash, path)
        expect(result[:success]).to be(true)
        expect(result[:filepath]).to eq(path)
        expect(File.exist?(path)).to be(true)
        content = File.read(path)
        parsed = JSON.parse(content)
        expect(parsed['user_id']).to eq('u1')
        expect(result[:size]).to eq(content.bytesize)
      end
    end

    it 'returns an error hash when write fails' do
      allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      result = reporter.export_to_json(report_hash, '/tmp/any.json')
      expect(result[:success]).to be(false)
      expect(result[:error]).to eq('disk full')
    end
  end

  describe '#compare_users' do
    it 'returns an error when fewer than 2 users are provided' do
      fixed_time = Time.parse('2024-01-01T00:00:00Z')
      allow(Time).to receive(:now).and_return(fixed_time)
      result = reporter.compare_users(['only-one'])
      expect(result[:error]).to be(true)
      expect(result[:message]).to eq('At least 2 users required')
      expect(result[:generated_at]).to eq(fixed_time.iso8601)
    end

    it 'compares users and sorts by engagement_score descending' do
      allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{ 'timestamp' => '2024-01-01T00:00:00Z', 'action' => 'a' }])
      allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{ 'timestamp' => '2024-01-01T00:00:00Z', 'action' => 'b' }])
      allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return(
        { total_actions: 10, unique_actions: 2, action_counts: {}, first_activity: 't1', last_activity: 't2', most_frequent: 'a' }
      )
      allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return(
        { total_actions: 20, unique_actions: 3, action_counts: {}, first_activity: 't3', last_activity: 't4', most_frequent: 'b' }
      )
      allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2024-01-01T00:00:00Z', 'action' => 'a' }]).and_return(60.0)
      allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2024-01-01T00:00:00Z', 'action' => 'b' }]).and_return(80.0)

      result = reporter.compare_users(['u1', 'u2'])

      expect(result[:total_users]).to eq(2)
      expect(result[:comparisons].map do |c|
        c[:user_id]
      end).to eq(['u2', 'u1'])
      top = result[:comparisons].first
      expect(top[:user_id]).to eq('u2')
      expect(top[:total_actions]).to eq(20)
      expect(top[:engagement_score]).to eq(80.0)
      expect(top[:most_frequent_action]).to eq('b')
      expect(result[:top_user]).to eq('u2')
      expect(result[:average_score]).to eq(70.0)
    end

    it 'handles three users and inserts into correct sorted positions' do
      allow(reporter).to receive(:fetch_user_activities).with('a').and_return([{ 'timestamp' => '2024-01-01T00:00:00Z', 'action' => 'x' }])
      allow(reporter).to receive(:fetch_user_activities).with('b').and_return([{ 'timestamp' => '2024-01-01T00:00:00Z', 'action' => 'y' }])
      allow(reporter).to receive(:fetch_user_activities).with('c').and_return([{ 'timestamp' => '2024-01-01T00:00:00Z', 'action' => 'z' }])

      allow(reporter).to receive(:fetch_activity_stats).with('a').and_return({ total_actions: 5, unique_actions: 1, action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'x' })
      allow(reporter).to receive(:fetch_activity_stats).with('b').and_return({ total_actions: 15, unique_actions: 2, action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'y' })
      allow(reporter).to receive(:fetch_activity_stats).with('c').and_return({ total_actions: 25, unique_actions: 3, action_counts: {}, first_activity: 't', last_activity: 't', most_frequent: 'z' })

      allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2024-01-01T00:00:00Z', 'action' => 'x' }]).and_return(50.0)
      allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2024-01-01T00:00:00Z', 'action' => 'y' }]).and_return(70.0)
      allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2024-01-01T00:00:00Z', 'action' => 'z' }]).and_return(60.0)

      result = reporter.compare_users(['a', 'b', 'c'])
      expect(result[:comparisons].map do |c|
        c[:user_id]
      end).to eq(['b', 'c', 'a'])
      expect(result[:top_user]).to eq('b')
      expect(result[:average_score]).to eq(((50.0 + 70.0 + 60.0) / 3.0).round(2))
    end
  end
end
