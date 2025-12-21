require 'spec_helper'
require 'json'
require 'tmpdir'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new
  end

  describe '#generate_report' do
    context 'when no activities are found for the user' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(123).and_return([])
      end

      it 'returns an error report with a helpful message' do
        result = reporter.generate_report(123)
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to be_a(String)
      end
    end

    context 'with activities and data available' do
      let(:user_id) do
        42
      end

      let(:activities) do
        [
          { 'timestamp' => '2024-01-01T10:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2024-01-01T12:00:00Z', 'action' => 'view' }
        ]
      end

      let(:stats) do
        {
          total_actions: 250,
          unique_actions: 12,
          action_counts: { 'click' => 150, 'view' => 100 },
          first_activity: '2024-01-01T09:00:00Z',
          last_activity: '2024-01-02T17:00:00Z',
          most_frequent: 'click'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'burst', 'description' => 'High morning activity', 'confidence' => 0.91 },
          { 'pattern_type' => 'habit', 'description' => 'Daily login', 'confidence' => 0.88 },
          { 'pattern_type' => 'sequence', 'description' => 'Click after view', 'confidence' => 0.77 }
        ]
      end

      let(:user_score) do
        82.5
      end

      let(:anomalies) do
        ['suspicious-login']
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a report including summary, patterns, anomalies, timeline, and insights' do
        result = reporter.generate_report(user_id, group_by: :day)
        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to be_a(String)

        expect(result[:summary][:total_actions]).to eq(250)
        expect(result[:summary][:unique_actions]).to eq(12)
        expect(result[:summary][:engagement_score]).to eq(82.5)
        expect(result[:summary][:first_activity]).to eq('2024-01-01T09:00:00Z')
        expect(result[:summary][:last_activity]).to eq('2024-01-02T17:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'click' => 150, 'view' => 100 })

        expect(result[:patterns]).to contain_exactly(
          { type: 'burst', description: 'High morning activity', confidence: 0.91 },
          { type: 'habit', description: 'Daily login', confidence: 0.88 },
          { type: 'sequence', description: 'Click after view', confidence: 0.77 }
        )

        expect(result[:anomalies]).to eq(anomalies)

        expect(result[:timeline].size).to eq(1)
        period = result[:timeline].first
        expect(period[:period]).to eq('2024-01-01')
        expect(period[:total_actions]).to eq(2)
        expect(period[:actions]).to eq({ 'click' => 1, 'view' => 1 })
        expect(period[:first_timestamp]).to eq('2024-01-01T10:00:00Z')
        expect(period[:last_timestamp]).to eq('2024-01-01T12:00:00Z')

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(result[:insights]).to include('Power user - high volume of activities')
      end

      it 'groups timeline by hour when requested' do
        result = reporter.generate_report(user_id, group_by: :hour)
        periods = result[:timeline].map { |p| p[:period] }
        expect(periods).to eq(['2024-01-01 10:00', '2024-01-01 12:00'])
      end

      it 'groups timeline by week and month' do
        week_result = reporter.generate_report(user_id, group_by: :week)
        month_result = reporter.generate_report(user_id, group_by: :month)

        expect(week_result[:timeline].map { |p| p[:period] }).to all(match(/\A\d{4}-W\d{2}\z/))
        expect(month_result[:timeline].map { |p| p[:period] }).to all(match(/\A\d{4}-\d{2}\z/))
      end

      it 'defaults to day grouping when an unknown group_by is provided' do
        result = reporter.generate_report(user_id, group_by: :unknown_grouping)
        expect(result[:timeline].first[:period]).to eq('2024-01-01')
      end
    end
  end

  describe '#format_timeline' do
    it 'returns empty array when activities are empty' do
      result = reporter.format_timeline([])
      expect(result).to eq([])
    end

    it 'groups activities by day and sorts periods ascending' do
      activities = [
        { 'timestamp' => '2023-01-02T10:00:00Z', 'action' => 'click' },
        { 'timestamp' => '2023-01-01T09:00:00Z', 'action' => 'view' },
        { 'timestamp' => '2023-01-02T11:00:00Z', 'action' => 'click' }
      ]
      result = reporter.format_timeline(activities, :day)
      expect(result.map { |r| r[:period] }).to eq(%w[2023-01-01 2023-01-02])

      jan2 = result.detect { |r| r[:period] == '2023-01-02' }
      expect(jan2[:total_actions]).to eq(2)
      expect(jan2[:actions]).to eq({ 'click' => 2 })
    end

    it 'falls back to current time when timestamp is invalid' do
      fixed = Time.utc(2022, 1, 2, 3, 4, 5)
      allow(Time).to receive(:now).and_return(fixed)
      activities = [
        { 'timestamp' => 'not-a-time', 'action' => 'click' }
      ]
      result = reporter.format_timeline(activities, :day)
      expect(result.size).to eq(1)
      expect(result.first[:period]).to eq('2022-01-02')
    end

    it 'defaults to day grouping when unknown group_by is given' do
      activities = [
        { 'timestamp' => '2024-02-03T10:00:00Z', 'action' => 'view' }
      ]
      result = reporter.format_timeline(activities, :unknown)
      expect(result.first[:period]).to eq('2024-02-03')
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 1,
        summary: { total_actions: 2 },
        timeline: []
      }
    end

    it 'returns JSON data when no filepath is provided' do
      result = reporter.export_to_json(report)
      expect(result[:success]).to be true
      expect(result[:data]).to be_a(String)
      parsed = JSON.parse(result[:data])
      expect(parsed['user_id']).to eq(1)
      expect(parsed['summary']['total_actions']).to eq(2)
    end

    it 'writes JSON to a file when filepath is provided' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(report, path)
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(path)
        expect(result[:size]).to be > 0
        expect(File.exist?(path)).to be true
        data = File.read(path)
        parsed = JSON.parse(data)
        expect(parsed['user_id']).to eq(1)
      end
    end

    it 'returns an error hash when writing fails' do
      allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      result = reporter.export_to_json(report, '/some/path/report.json')
      expect(result[:success]).to be false
      expect(result[:error]).to eq('disk full')
    end
  end

  describe '#compare_users' do
    it 'returns an error report when fewer than 2 users are provided' do
      result = reporter.compare_users([7])
      expect(result[:error]).to be true
      expect(result[:message]).to eq('At least 2 users required')
    end

    it 'compares multiple users, sorts by engagement score, and computes average' do
      user_ids = [1, 2, 3]

      allow(reporter).to receive(:fetch_user_activities).with(1).and_return([{ 'timestamp' => '2024-01-01T00:00:00Z',
                                                                               'action' => 'a' }])
      allow(reporter).to receive(:fetch_user_activities).with(2).and_return([{ 'timestamp' => '2024-01-01T00:00:00Z',
                                                                               'action' => 'b' }])
      allow(reporter).to receive(:fetch_user_activities).with(3).and_return([{ 'timestamp' => '2024-01-01T00:00:00Z',
                                                                               'action' => 'c' }])

      allow(reporter).to receive(:fetch_activity_stats).with(1).and_return({ total_actions: 10, unique_actions: 2,
                                                                             action_counts: {}, first_activity: '2024-01-01T00:00:00Z', last_activity: '2024-01-01T00:00:00Z', most_frequent: 'a' })
      allow(reporter).to receive(:fetch_activity_stats).with(2).and_return({ total_actions: 5, unique_actions: 1,
                                                                             action_counts: {}, first_activity: '2024-01-01T00:00:00Z', last_activity: '2024-01-01T00:00:00Z', most_frequent: 'b' })
      allow(reporter).to receive(:fetch_activity_stats).with(3).and_return({ total_actions: 20, unique_actions: 3,
                                                                             action_counts: {}, first_activity: '2024-01-01T00:00:00Z', last_activity: '2024-01-01T00:00:00Z', most_frequent: 'c' })

      allow(reporter).to receive(:fetch_user_score).and_return(70, 90, 80)

      result = reporter.compare_users(user_ids)

      expect(result[:total_users]).to eq(3)
      expect(result[:top_user]).to eq(2)
      expect(result[:average_score]).to eq(80.0)
      expect(result[:comparisons].map { |c| c[:user_id] }).to eq([2, 3, 1])

      top = result[:comparisons].first
      expect(top[:user_id]).to eq(2)
      expect(top[:engagement_score]).to eq(90)
      expect(top[:most_frequent_action]).to eq('b')

      bottom = result[:comparisons].last
      expect(bottom[:user_id]).to eq(1)
      expect(bottom[:total_actions]).to eq(10)
    end
  end
end
