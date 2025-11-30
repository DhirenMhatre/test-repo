require 'spec_helper'
require 'time'
require 'json'
require 'tmpdir'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  describe '#initialize' do
    it 'initializes with default service URLs' do
      instance = described_class.new
      expect(instance).to be_a(ActivityReporter)
    end

    it 'initializes with custom service URLs' do
      instance = described_class.new(go_service_url: 'http://go', python_service_url: 'http://py')
      expect(instance).to be_a(ActivityReporter)
    end
  end

  describe '#generate_report' do
    let(:reporter) do
      described_class.new
    end

    let(:user_id) do
      'user-123'
    end

    let(:fixed_time) do
      Time.parse('2023-05-01T12:00:00Z')
    end

    let(:activities) do
      [
        { 'timestamp' => '2023-04-30T10:15:00Z', 'action' => 'click' },
        { 'timestamp' => '2023-04-30T12:30:00Z', 'action' => 'view' },
        { 'timestamp' => '2023-05-01T09:00:00Z', 'action' => 'click' },
        { 'timestamp' => '2023-05-01T10:00:00Z', 'action' => 'click' }
      ]
    end

    let(:stats) do
      {
        total_actions: 4,
        unique_actions: 2,
        action_counts: { 'click' => 3, 'view' => 1 },
        first_activity: '2023-04-30T10:15:00Z',
        last_activity: '2023-05-01T10:00:00Z',
        most_frequent: 'click'
      }
    end

    let(:raw_patterns) do
      [
        { 'pattern_type' => 'burst', 'description' => 'Morning activity peak', 'confidence' => 0.9 },
        { 'pattern_type' => 'routine', 'description' => 'Daily login', 'confidence' => 0.8 },
        { 'pattern_type' => 'weekly', 'description' => 'Weekly summary read', 'confidence' => 0.7 }
      ]
    end

    let(:anomalies) do
      [{ id: 1, type: 'spike' }]
    end

    before do
      allow(Time).to receive(:now).and_return(fixed_time)
    end

    context 'when activities are present' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(raw_patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(80.5)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'returns a comprehensive report with expected structure and values' do
        result = reporter.generate_report(user_id, group_by: :day)

        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(fixed_time.iso8601)

        expect(result[:summary][:total_actions]).to eq(4)
        expect(result[:summary][:unique_actions]).to eq(2)
        expect(result[:summary][:engagement_score]).to eq(80.5)
        expect(result[:summary][:first_activity]).to eq('2023-04-30T10:15:00Z')
        expect(result[:summary][:last_activity]).to eq('2023-05-01T10:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'click' => 3, 'view' => 1 })

        expect(result[:patterns]).to contain_exactly(
          { type: 'burst', description: 'Morning activity peak', confidence: 0.9 },
          { type: 'routine', description: 'Daily login', confidence: 0.8 },
          { type: 'weekly', description: 'Weekly summary read', confidence: 0.7 }
        )

        expect(result[:anomalies]).to eq(anomalies)

        periods = result[:timeline].map { |e| e[:period] }
        expect(periods).to eq(%w[2023-04-30 2023-05-01])

        day1 = result[:timeline].find { |e| e[:period] == '2023-04-30' }
        expect(day1[:total_actions]).to eq(2)
        expect(day1[:actions]).to eq({ 'click' => 1, 'view' => 1 })
        expect(day1[:first_timestamp]).to eq('2023-04-30T10:15:00Z')
        expect(day1[:last_timestamp]).to eq('2023-04-30T12:30:00Z')

        day2 = result[:timeline].find { |e| e[:period] == '2023-05-01' }
        expect(day2[:total_actions]).to eq(2)
        expect(day2[:actions]).to eq({ 'click' => 2 })
        expect(day2[:first_timestamp]).to eq('2023-05-01T09:00:00Z')
        expect(day2[:last_timestamp]).to eq('2023-05-01T10:00:00Z')

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(result[:insights]).not_to include('Low engagement - consider re-engagement strategies')
      end
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
        expect(reporter).not_to receive(:fetch_activity_stats)
        expect(reporter).not_to receive(:fetch_activity_patterns)
        expect(reporter).not_to receive(:fetch_user_score)
        expect(reporter).not_to receive(:fetch_anomalies)
      end

      it 'returns an error report' do
        result = reporter.generate_report(user_id)
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) do
      described_class.new
    end

    it 'returns empty array when no activities' do
      expect(reporter.format_timeline([])).to eq([])
    end

    it 'groups by day by default' do
      activities = [
        { 'timestamp' => '2023-04-30T10:15:00Z', 'action' => 'click' },
        { 'timestamp' => '2023-04-30T12:30:00Z', 'action' => 'view' },
        { 'timestamp' => '2023-05-01T09:00:00Z', 'action' => 'click' }
      ]
      result = reporter.format_timeline(activities)
      expect(result.map { |e| e[:period] }).to eq(%w[2023-04-30 2023-05-01])
    end

    it 'groups by hour when specified' do
      activities = [
        { 'timestamp' => '2023-04-30T10:15:00Z', 'action' => 'click' },
        { 'timestamp' => '2023-04-30T10:59:00Z', 'action' => 'view' },
        { 'timestamp' => '2023-04-30T11:00:00Z', 'action' => 'click' }
      ]
      result = reporter.format_timeline(activities, :hour)
      expect(result.map { |e| e[:period] }).to eq(['2023-04-30 10:00', '2023-04-30 11:00'])
      hour10 = result.find { |e| e[:period] == '2023-04-30 10:00' }
      expect(hour10[:actions]).to eq({ 'click' => 1, 'view' => 1 })
    end

    it 'groups by week when specified' do
      activities = [
        { 'timestamp' => '2023-01-02T08:00:00Z', 'action' => 'a' },
        { 'timestamp' => '2023-01-03T08:00:00Z', 'action' => 'b' }
      ]
      result = reporter.format_timeline(activities, :week)
      expect(result.map { |e| e[:period] }).to eq(['2023-W01'])
    end

    it 'groups by month when specified' do
      activities = [
        { 'timestamp' => '2023-04-10T00:00:00Z', 'action' => 'a' },
        { 'timestamp' => '2023-04-20T00:00:00Z', 'action' => 'a' },
        { 'timestamp' => '2023-05-01T00:00:00Z', 'action' => 'b' }
      ]
      result = reporter.format_timeline(activities, :month)
      expect(result.map { |e| e[:period] }).to eq(%w[2023-04 2023-05])
      april = result.find { |e| e[:period] == '2023-04' }
      expect(april[:total_actions]).to eq(2)
    end

    it 'falls back to day grouping for unknown group_by values' do
      activities = [
        { 'timestamp' => '2023-04-30T10:15:00Z', 'action' => 'x' }
      ]
      result = reporter.format_timeline(activities, :foo)
      expect(result.map { |e| e[:period] }).to eq(['2023-04-30'])
    end

    it 'handles invalid timestamps by using current time' do
      fixed_time = Time.parse('2023-06-15T00:00:00Z')
      allow(Time).to receive(:now).and_return(fixed_time)
      activities = [
        { 'timestamp' => 'invalid', 'action' => 'x' }
      ]
      result = reporter.format_timeline(activities, :day)
      expect(result.map { |e| e[:period] }).to eq(['2023-06-15'])
      expect(result.first[:first_timestamp]).to eq('invalid')
      expect(result.first[:last_timestamp]).to eq('invalid')
    end

    it 'preserves first and last timestamps based on original order within a period' do
      activities = [
        { 'timestamp' => '2023-04-30T12:00:00Z', 'action' => 'x' },
        { 'timestamp' => '2023-04-30T11:00:00Z', 'action' => 'y' }
      ]
      result = reporter.format_timeline(activities, :day)
      entry = result.first
      expect(entry[:first_timestamp]).to eq('2023-04-30T12:00:00Z')
      expect(entry[:last_timestamp]).to eq('2023-04-30T11:00:00Z')
    end
  end

  describe '#export_to_json' do
    let(:reporter) do
      described_class.new
    end

    let(:report) do
      {
        user_id: 'u1',
        summary: { total_actions: 2 },
        timeline: []
      }
    end

    it 'returns pretty JSON data when no filepath is provided' do
      result = reporter.export_to_json(report)
      expect(result[:success]).to eq(true)
      expect(JSON.parse(result[:data])).to eq(JSON.parse(JSON.pretty_generate(report)))
    end

    it 'writes JSON to a file when filepath is provided' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(report, path)
        expect(result[:success]).to eq(true)
        expect(result[:filepath]).to eq(path)
        expect(File.exist?(path)).to eq(true)
        content = File.read(path)
        expect(content).to eq(JSON.pretty_generate(report))
        expect(result[:size]).to eq(content.bytesize)
      end
    end

    it 'returns error when file write fails' do
      allow(File).to receive(:write).and_raise(StandardError, 'disk full')
      result = reporter.export_to_json(report, '/unwritable/path.json')
      expect(result[:success]).to eq(false)
      expect(result[:error]).to eq('disk full')
    end

    it 'returns error when JSON serialization fails' do
      allow(JSON).to receive(:pretty_generate).and_raise(StandardError, 'bad data')
      result = reporter.export_to_json(report)
      expect(result[:success]).to eq(false)
      expect(result[:error]).to eq('bad data')
    end
  end

  describe '#compare_users' do
    let(:reporter) do
      described_class.new
    end

    context 'when fewer than 2 users are provided' do
      it 'returns an error report' do
        fixed_time = Time.parse('2023-07-01T00:00:00Z')
        allow(Time).to receive(:now).and_return(fixed_time)
        result = reporter.compare_users([1])
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with multiple users' do
      it 'returns sorted comparisons with top user and average score' do
        allow(reporter).to receive(:fetch_user_activities).with(1).and_return([:a])
        allow(reporter).to receive(:fetch_user_activities).with(2).and_return([:b])
        allow(reporter).to receive(:fetch_user_activities).with(3).and_return([:c])

        allow(reporter).to receive(:fetch_activity_stats).with(1).and_return(
          { total_actions: 5, unique_actions: 2, action_counts: {}, first_activity: 't1', last_activity: 't2',
            most_frequent: 'view' }
        )
        allow(reporter).to receive(:fetch_activity_stats).with(2).and_return(
          { total_actions: 10, unique_actions: 3, action_counts: {}, first_activity: 't1', last_activity: 't2',
            most_frequent: 'click' }
        )
        allow(reporter).to receive(:fetch_activity_stats).with(3).and_return(
          { total_actions: 1, unique_actions: 1, action_counts: {}, first_activity: 't1', last_activity: 't2',
            most_frequent: 'like' }
        )

        allow(reporter).to receive(:fetch_user_score).and_return(90.0, 70.0, 10.0)

        result = reporter.compare_users([1, 2, 3])

        expect(result[:total_users]).to eq(3)
        expect(result[:top_user]).to eq(1)
        expect(result[:average_score]).to eq(56.67)

        expect(result[:comparisons].map { |c| c[:user_id] }).to eq([1, 2, 3])
        expect(result[:comparisons].map { |c| c[:engagement_score] }).to eq([90.0, 70.0, 10.0])

        comp1 = result[:comparisons].find { |c| c[:user_id] == 1 }
        expect(comp1[:total_actions]).to eq(5)
        expect(comp1[:most_frequent_action]).to eq('view')
      end
    end
  end
end
