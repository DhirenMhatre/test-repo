require 'spec_helper'
require 'time'
require 'tmpdir'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  describe '#initialize' do
    it 'initializes with default URLs without error' do
      expect do
        described_class.new
      end.not_to raise_error
    end

    it 'accepts custom service URLs without error' do
      expect do
        described_class.new(go_service_url: 'http://go.example.com', python_service_url: 'http://py.example.com')
      end.not_to raise_error
    end
  end

  describe '#generate_report' do
    let(:reporter) do
      described_class.new
    end

    let(:fixed_now) do
      Time.parse('2025-01-10T12:34:56Z')
    end

    before do
      allow(Time).to receive(:now).and_return(fixed_now)
    end

    context 'when no activities are found' do
      it 'returns an error report with appropriate message' do
        allow(reporter).to receive(:fetch_user_activities).with(123).and_return([])
        result = reporter.generate_report(123)
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_now.iso8601)
      end
    end

    context 'with activities and full data' do
      let(:user_id) do
        42
      end

      let(:activities) do
        [
          { 'action' => 'login', 'timestamp' => '2025-01-01T10:45:00Z' },
          { 'action' => 'click', 'timestamp' => '2025-01-01T10:15:00Z' },
          { 'action' => 'purchase', 'timestamp' => '2025-01-02T11:20:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 11,
          action_counts: { 'login' => 50, 'click' => 70, 'purchase' => 30 },
          first_activity: '2025-01-01T00:00:00Z',
          last_activity: '2025-01-05T00:00:00Z',
          most_frequent: 'click'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'streak', 'description' => 'Daily login streak', 'confidence' => 0.92 },
          { 'pattern_type' => 'cluster', 'description' => 'Evening activity cluster', 'confidence' => 0.81 },
          { 'pattern_type' => 'sequence', 'description' => 'Click after login', 'confidence' => 0.76 }
        ]
      end

      let(:user_score) do
        88.5
      end

      let(:anomalies) do
        [
          { id: 1, reason: 'suspicious_ip' },
          { id: 2, reason: 'unusual_time' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'generates a comprehensive report with correct fields and insights (group_by day default)' do
        report = reporter.generate_report(user_id)
        expect(report[:user_id]).to eq(user_id)
        expect(report[:generated_at]).to eq(fixed_now.iso8601)

        expect(report[:summary][:total_actions]).to eq(150)
        expect(report[:summary][:unique_actions]).to eq(11)
        expect(report[:summary][:engagement_score]).to eq(user_score)
        expect(report[:summary][:first_activity]).to eq('2025-01-01T00:00:00Z')
        expect(report[:summary][:last_activity]).to eq('2025-01-05T00:00:00Z')

        expect(report[:action_breakdown]).to eq({ 'login' => 50, 'click' => 70, 'purchase' => 30 })

        expect(report[:patterns]).to eq([
          { type: 'streak', description: 'Daily login streak', confidence: 0.92 },
          { type: 'cluster', description: 'Evening activity cluster', confidence: 0.81 },
          { type: 'sequence', description: 'Click after login', confidence: 0.76 }
        ])

        expect(report[:anomalies]).to eq(anomalies)

        # Timeline default to day
        expect(report[:timeline].map { |t| t[:period] }).to eq(['2025-01-01', '2025-01-02'])
        # For 2025-01-01 group, acts order should reflect original enumeration: first timestamp is 10:45, last 10:15
        day1 = report[:timeline].find do |t|
          t[:period] == '2025-01-01'
        end
        expect(day1[:total_actions]).to eq(2)
        expect(day1[:actions]).to eq({ 'login' => 1, 'click' => 1 })
        expect(day1[:first_timestamp]).to eq('2025-01-01T10:45:00Z')
        expect(day1[:last_timestamp]).to eq('2025-01-01T10:15:00Z')

        day2 = report[:timeline].find do |t|
          t[:period] == '2025-01-02'
        end
        expect(day2[:total_actions]).to eq(1)
        expect(day2[:actions]).to eq({ 'purchase' => 1 })

        insights = report[:insights]
        expect(insights).to include('Highly engaged user with strong activity patterns')
        expect(insights).to include('Diverse activity profile across multiple action types')
        expect(insights).to include('Clear behavioral patterns detected')
        expect(insights).to include('2 anomalous activities detected - review recommended')
        expect(insights).to include('Power user - high volume of activities')
      end

      it 'honors group_by option when provided (hour)' do
        report = reporter.generate_report(user_id, group_by: :hour)
        expect(report[:timeline].map { |t| t[:period] }).to eq(['2025-01-01 10:00', '2025-01-02 11:00'])
      end
    end

    context 'with low engagement metrics' do
      let(:user_id) do
        7
      end

      let(:activities) do
        [
          { 'action' => 'view', 'timestamp' => '2025-02-01T09:00:00Z' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 2,
          action_counts: { 'view' => 3 },
          first_activity: '2025-02-01T09:00:00Z',
          last_activity: '2025-02-01T09:30:00Z',
          most_frequent: 'view'
        }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return([])
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(30.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([])
      end

      it 'generates insights indicating low engagement' do
        report = reporter.generate_report(user_id)
        expect(report[:insights]).to include('Low engagement - consider re-engagement strategies')
        expect(report[:insights]).not_to include('Clear behavioral patterns detected')
        expect(report[:insights]).not_to include('Power user - high volume of activities')
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) do
      described_class.new
    end

    let(:fixed_now) do
      Time.parse('2025-01-02T00:30:00Z')
    end

    before do
      allow(Time).to receive(:now).and_return(fixed_now)
    end

    it 'returns empty array for empty activities' do
      expect(reporter.format_timeline([], :day)).to eq([])
    end

    it 'groups activities by hour and sorts by period string' do
      activities = [
        { 'action' => 'a', 'timestamp' => '2025-01-01T10:45:00Z' },
        { 'action' => 'b', 'timestamp' => '2025-01-01T10:15:00Z' },
        { 'action' => 'c', 'timestamp' => '2025-01-01T11:05:00Z' },
        { 'action' => 'd', 'timestamp' => 'invalid' }
      ]
      tl = reporter.format_timeline(activities, :hour)
      expect(tl.map { |t| t[:period] }).to eq(['2025-01-01 10:00', '2025-01-01 11:00', '2025-01-02 00:00'])

      bucket_10 = tl.find do |t|
        t[:period] == '2025-01-01 10:00'
      end
      expect(bucket_10[:total_actions]).to eq(2)
      expect(bucket_10[:actions]).to eq({ 'a' => 1, 'b' => 1 })
      expect(bucket_10[:first_timestamp]).to eq('2025-01-01T10:45:00Z')
      expect(bucket_10[:last_timestamp]).to eq('2025-01-01T10:15:00Z')
    end

    it 'groups activities by day by default when given unknown group' do
      activities = [
        { 'action' => 'x', 'timestamp' => '2025-03-01T08:00:00Z' },
        { 'action' => 'y', 'timestamp' => '2025-03-01T12:00:00Z' }
      ]
      tl = reporter.format_timeline(activities, :unknown)
      expect(tl.length).to eq(1)
      expect(tl.first[:period]).to eq('2025-03-01')
    end

    it 'groups activities by week using ISO week format' do
      activities = [
        { 'action' => 'x', 'timestamp' => '2025-01-06T00:00:00Z' },
        { 'action' => 'y', 'timestamp' => '2025-01-07T12:00:00Z' }
      ]
      tl = reporter.format_timeline(activities, :week)
      expect(tl.length).to eq(1)
      expect(tl.first[:period]).to match(/\A2025-W\d{2}\z/)
    end

    it 'groups activities by month' do
      activities = [
        { 'action' => 'x', 'timestamp' => '2025-01-31T23:59:59Z' },
        { 'action' => 'y', 'timestamp' => '2025-02-01T00:00:00Z' }
      ]
      tl = reporter.format_timeline(activities, :month)
      expect(tl.map { |t| t[:period] }).to eq(['2025-01', '2025-02'])
    end
  end

  describe '#export_to_json' do
    let(:reporter) do
      described_class.new
    end

    it 'returns pretty JSON data when no filepath is provided' do
      payload = { user_id: 1, summary: { total_actions: 3 } }
      result = reporter.export_to_json(payload)
      expect(result[:success]).to be true
      expect(result[:data]).to be_a(String)
      parsed = JSON.parse(result[:data])
      expect(parsed['user_id']).to eq(1)
      expect(parsed['summary']['total_actions']).to eq(3)
    end

    it 'writes JSON to file and returns metadata when filepath is provided' do
      payload = { user_id: 2, summary: { total_actions: 5 } }
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(payload, path)
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(path)
        expect(result[:size]).to eq(JSON.pretty_generate(payload).bytesize)
        content = File.read(path)
        parsed = JSON.parse(content)
        expect(parsed['user_id']).to eq(2)
        expect(parsed['summary']['total_actions']).to eq(5)
      end
    end

    it 'returns error when file writing fails' do
      payload = { ok: true }
      allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      result = reporter.export_to_json(payload, '/tmp/fail.json')
      expect(result[:success]).to be false
      expect(result[:error]).to eq('disk full')
    end
  end

  describe '#compare_users' do
    let(:reporter) do
      described_class.new
    end

    it 'returns an error report if fewer than two users provided' do
      result = reporter.compare_users([123])
      expect(result[:error]).to be true
      expect(result[:message]).to eq('At least 2 users required')
    end

    it 'compares multiple users and sorts by engagement score descending' do
      user_ids = [2, 1, 3]

      activities_map = {
        1 => [{ 'action' => 'a', 'timestamp' => '2025-01-01T00:00:00Z' }],
        2 => [{ 'action' => 'b', 'timestamp' => '2025-01-01T00:00:00Z' }],
        3 => [{ 'action' => 'c', 'timestamp' => '2025-01-01T00:00:00Z' }]
      }

      stats_map = {
        1 => { total_actions: 10, unique_actions: 3, action_counts: { 'a' => 10 }, first_activity: '2025-01-01T00:00:00Z', last_activity: '2025-01-02T00:00:00Z', most_frequent: 'a' },
        2 => { total_actions: 8, unique_actions: 2, action_counts: { 'b' => 8 }, first_activity: '2025-01-01T00:00:00Z', last_activity: '2025-01-02T00:00:00Z', most_frequent: 'b' },
        3 => { total_actions: 12, unique_actions: 4, action_counts: { 'c' => 12 }, first_activity: '2025-01-01T00:00:00Z', last_activity: '2025-01-02T00:00:00Z', most_frequent: 'c' }
      }

      score_map = {
        1 => 90.0,
        2 => 80.0,
        3 => 80.0
      }

      allow(reporter).to receive(:fetch_user_activities) do |uid|
        activities_map[uid]
      end

      allow(reporter).to receive(:fetch_activity_stats) do |uid|
        stats_map[uid]
      end

      allow(reporter).to receive(:fetch_user_score) do |acts|
        uid = activities_map.key(acts)
        score_map[uid]
      end

      result = reporter.compare_users(user_ids)

      expect(result[:total_users]).to eq(3)
      expect(result[:comparisons].map { |c| c[:user_id] }).to eq([1, 2, 3])
      # Users 2 and 3 have equal score; order follows input order among equals (2 before 3)
      comp_1 = result[:comparisons].find do |c|
        c[:user_id] == 1
      end
      expect(comp_1[:total_actions]).to eq(10)
      expect(comp_1[:engagement_score]).to eq(90.0)
      expect(comp_1[:most_frequent_action]).to eq('a')

      expect(result[:top_user]).to eq(1)
      expect(result[:average_score]).to eq(((90.0 + 80.0 + 80.0) / 3.0).round(2))
    end
  end
end
