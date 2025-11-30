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

  describe '#generate_report' do
    let(:user_id) do
      'user-1'
    end

    context 'when no activities are found' do
      it 'returns an error report and skips downstream fetches' do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
        expect(reporter).not_to receive(:fetch_activity_stats)
        expect(reporter).not_to receive(:fetch_activity_patterns)
        expect(reporter).not_to receive(:fetch_user_score)
        expect(reporter).not_to receive(:fetch_anomalies)

        result = reporter.generate_report(user_id)

        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to be_a(String)
        expect do
          Time.iso8601(result[:generated_at])
        end.not_to raise_error
      end
    end

    context 'with activities present (default daily grouping)' do
      let(:activities) do
        [
          { 'timestamp' => '2023-01-01T10:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2023-01-01T11:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-01-02T09:00:00Z', 'action' => 'purchase' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 3,
          action_counts: { 'login' => 1, 'click' => 1, 'purchase' => 1 },
          first_activity: '2023-01-01T10:15:00Z',
          last_activity: '2023-01-02T09:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'streak', 'description' => 'daily habit', 'confidence' => 0.8 }
        ]
      end

      let(:anomalies) do
        [
          { 'id' => 1, 'reason' => 'suspicious' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(80.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'assembles a complete report with formatted patterns and insights' do
        report = reporter.generate_report(user_id)

        expect(report[:user_id]).to eq(user_id)
        expect(report[:summary][:total_actions]).to eq(3)
        expect(report[:summary][:unique_actions]).to eq(3)
        expect(report[:summary][:engagement_score]).to eq(80.0)
        expect(report[:summary][:first_activity]).to eq('2023-01-01T10:15:00Z')
        expect(report[:summary][:last_activity]).to eq('2023-01-02T09:00:00Z')

        expect(report[:action_breakdown]).to eq({ 'login' => 1, 'click' => 1, 'purchase' => 1 })

        expect(report[:patterns]).to eq([
                                          { type: 'streak', description: 'daily habit', confidence: 0.8 }
                                        ])

        expect(report[:anomalies]).to eq(anomalies)

        expect(report[:timeline]).to be_an(Array)
        expect(report[:timeline].map { |t| t[:period] }).to eq(%w[2023-01-01 2023-01-02])
        expect(report[:timeline].find { |t| t[:period] == '2023-01-01' }[:total_actions]).to eq(2)
        expect(report[:timeline].find { |t| t[:period] == '2023-01-02' }[:total_actions]).to eq(1)

        insights = report[:insights]
        expect(insights).to include('Highly engaged user with strong activity patterns')
        expect(insights.any? { |i| i.include?('anomalous activities detected') }).to be true
        expect(insights).not_to include('Moderately engaged user with regular activity')
        expect(insights).not_to include('Low engagement - consider re-engagement strategies')

        expect do
          Time.iso8601(report[:generated_at])
        end.not_to raise_error
      end

      it 'uses the provided group_by option when generating timeline' do
        report = reporter.generate_report(user_id, { group_by: :month })

        expect(report[:timeline].map { |t| t[:period] }.uniq).to eq(['2023-01'])
        expect(report[:timeline].first[:total_actions]).to eq(3)
        expect(report[:timeline].first[:actions]).to eq({ 'login' => 1, 'click' => 1, 'purchase' => 1 })
      end
    end

    context 'insight generation for low engagement and diverse patterns' do
      let(:activities) do
        [
          { 'timestamp' => '2023-02-01T10:00:00Z', 'action' => 'a1' },
          { 'timestamp' => '2023-02-01T10:05:00Z', 'action' => 'a2' }
        ]
      end

      let(:stats) do
        {
          total_actions: 120,
          unique_actions: 11,
          action_counts: { 'a1' => 60, 'a2' => 60 },
          first_activity: '2023-02-01T10:00:00Z',
          last_activity: '2023-02-01T10:05:00Z',
          most_frequent: 'a1'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'p1', 'description' => 'd1', 'confidence' => 0.9 },
          { 'pattern_type' => 'p2', 'description' => 'd2', 'confidence' => 0.7 },
          { 'pattern_type' => 'p3', 'description' => 'd3', 'confidence' => 0.6 }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(40.0)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return([])
      end

      it 'includes low engagement, diversity, clear patterns, and power user insights' do
        report = reporter.generate_report(user_id)

        insights = report[:insights]
        expect(insights).to include('Low engagement - consider re-engagement strategies')
        expect(insights).to include('Diverse activity profile across multiple action types')
        expect(insights).to include('Clear behavioral patterns detected')
        expect(insights).to include('Power user - high volume of activities')
        expect(insights).not_to include('Moderately engaged user with regular activity')
        expect(insights).not_to include('Highly engaged user with strong activity patterns')
      end
    end
  end

  describe '#format_timeline' do
    let(:activities) do
      [
        { 'timestamp' => '2023-01-01T12:00:00Z', 'action' => 'login' },
        { 'timestamp' => '2023-01-01T08:00:00Z', 'action' => 'click' },
        { 'timestamp' => '2023-01-02T09:00:00Z', 'action' => 'purchase' }
      ]
    end

    it 'returns empty array when activities are empty' do
      result = reporter.format_timeline([], :day)
      expect(result).to eq([])
    end

    it 'groups by day and sorts periods ascending' do
      result = reporter.format_timeline(activities, :day)
      expect(result.map { |e| e[:period] }).to eq(%w[2023-01-01 2023-01-02])
      day1 = result.find { |e| e[:period] == '2023-01-01' }
      expect(day1[:total_actions]).to eq(2)
      expect(day1[:actions]).to eq({ 'login' => 1, 'click' => 1 })
      expect(day1[:first_timestamp]).to eq('2023-01-01T12:00:00Z')
      expect(day1[:last_timestamp]).to eq('2023-01-01T08:00:00Z')
    end

    it 'groups by hour' do
      result = reporter.format_timeline(activities, :hour)
      expect(result.map { |e| e[:period] }).to include('2023-01-01 12:00', '2023-01-01 08:00', '2023-01-02 09:00')
      hour_bucket = result.find { |e| e[:period] == '2023-01-02 09:00' }
      expect(hour_bucket[:total_actions]).to eq(1)
      expect(hour_bucket[:actions]).to eq({ 'purchase' => 1 })
    end

    it 'groups by week using ISO week numbers' do
      weekly_activities = [
        { 'timestamp' => '2023-01-04T10:00:00Z', 'action' => 'a' }, # ISO week 01
        { 'timestamp' => '2023-01-10T10:00:00Z', 'action' => 'b' }  # ISO week 02
      ]
      result = reporter.format_timeline(weekly_activities, :week)
      expect(result.map { |e| e[:period] }).to eq(%w[2023-W01 2023-W02])
      expect(result.first[:total_actions]).to eq(1)
      expect(result.last[:total_actions]).to eq(1)
    end

    it 'groups by month' do
      monthly_activities = [
        { 'timestamp' => '2023-01-31T23:59:59Z', 'action' => 'a' },
        { 'timestamp' => '2023-01-01T00:00:00Z', 'action' => 'b' }
      ]
      result = reporter.format_timeline(monthly_activities, :month)
      expect(result.map { |e| e[:period] }).to eq(['2023-01'])
      expect(result.first[:total_actions]).to eq(2)
      expect(result.first[:actions]).to eq({ 'a' => 1, 'b' => 1 })
    end

    it 'handles invalid timestamps by using parse_timestamp fallback and preserves original first/last values' do
      bad_activities = [
        { 'timestamp' => 'not-a-time', 'action' => 'x' },
        { 'timestamp' => 'still-bad', 'action' => 'y' }
      ]
      allow(reporter).to receive(:parse_timestamp).and_return(Time.parse('2023-05-01T00:00:00Z'))

      result = reporter.format_timeline(bad_activities, :day)

      expect(result.length).to eq(1)
      expect(result.first[:period]).to eq('2023-05-01')
      expect(result.first[:first_timestamp]).to eq('not-a-time')
      expect(result.first[:last_timestamp]).to eq('still-bad')
    end
  end

  describe '#export_to_json' do
    let(:report_hash) do
      {
        user_id: 'u-123',
        generated_at: Time.now.iso8601,
        summary: { total_actions: 2 },
        action_breakdown: { 'a' => 1, 'b' => 1 },
        patterns: [],
        anomalies: [],
        timeline: [],
        insights: []
      }
    end

    it 'returns pretty JSON data when no filepath is provided' do
      result = reporter.export_to_json(report_hash)
      expect(result[:success]).to eq(true)
      expect(result[:data]).to be_a(String)

      parsed = JSON.parse(result[:data])
      expected = JSON.parse(JSON.pretty_generate(report_hash))
      expect(parsed).to eq(expected)
    end

    it 'writes JSON to the given filepath' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(report_hash, path)

        expect(result[:success]).to eq(true)
        expect(result[:filepath]).to eq(path)
        expect(result[:size]).to be > 0

        content = File.read(path)
        parsed = JSON.parse(content)
        expected = JSON.parse(JSON.pretty_generate(report_hash))
        expect(parsed).to eq(expected)
      end
    end

    it 'returns an error when file writing fails' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        allow(File).to receive(:write).with(path, kind_of(String)).and_raise(StandardError.new('disk full'))

        result = reporter.export_to_json(report_hash, path)

        expect(result[:success]).to eq(false)
        expect(result[:error]).to eq('disk full')
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with multiple users' do
      let(:user_ids) do
        %w[a b c]
      end

      let(:a_acts) do
        [{ 'timestamp' => '2023-01-01T00:00:00Z', 'action' => 'x' }]
      end

      let(:b_acts) do
        [{ 'timestamp' => '2023-01-02T00:00:00Z', 'action' => 'y' }]
      end

      let(:c_acts) do
        [{ 'timestamp' => '2023-01-03T00:00:00Z', 'action' => 'z' }]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('a').and_return(a_acts)
        allow(reporter).to receive(:fetch_user_activities).with('b').and_return(b_acts)
        allow(reporter).to receive(:fetch_user_activities).with('c').and_return(c_acts)

        allow(reporter).to receive(:fetch_activity_stats).with('a').and_return({
                                                                                 total_actions: 10, unique_actions: 2, action_counts: {}, first_activity: 't1', last_activity: 't2', most_frequent: 'x'
                                                                               })
        allow(reporter).to receive(:fetch_activity_stats).with('b').and_return({
                                                                                 total_actions: 50, unique_actions: 5, action_counts: {}, first_activity: 't1', last_activity: 't2', most_frequent: 'y'
                                                                               })
        allow(reporter).to receive(:fetch_activity_stats).with('c').and_return({
                                                                                 total_actions: 20, unique_actions: 3, action_counts: {}, first_activity: 't1', last_activity: 't2', most_frequent: 'z'
                                                                               })

        allow(reporter).to receive(:fetch_user_score).with(a_acts).and_return(45.2)
        allow(reporter).to receive(:fetch_user_score).with(b_acts).and_return(87.1)
        allow(reporter).to receive(:fetch_user_score).with(c_acts).and_return(50.0)
      end

      it 'returns comparisons sorted by engagement score with correct aggregates' do
        result = reporter.compare_users(user_ids)

        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].length).to eq(3)

        # Sorted descending by engagement score: b, c, a
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[b c a])
        expect(result[:comparisons].first[:engagement_score]).to eq(87.1)
        expect(result[:comparisons].first[:most_frequent_action]).to eq('y')
        expect(result[:top_user]).to eq('b')

        expect(result[:average_score]).to eq(60.77)
      end
    end
  end
end
