require 'spec_helper'
require 'json'
require 'tmpdir'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:go_url) { 'http://go.example:8080' }
  let(:py_url) { 'http://py.example:8081' }
  let(:reporter) { described_class.new(go_service_url: go_url, python_service_url: py_url) }

  describe '#initialize' do
    it 'sets the provided service URLs' do
      expect(reporter.instance_variable_get(:@go_service_url)).to eq(go_url)
      expect(reporter.instance_variable_get(:@python_service_url)).to eq(py_url)
    end

    it 'uses default URLs when none are provided' do
      r = described_class.new
      expect(r.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
      expect(r.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
    end
  end

  describe '#generate_report' do
    let(:user_id) { 42 }
    let(:activities) do
      [
        { 'timestamp' => '2025-01-01T09:00:00Z', 'action' => 'login' },
        { 'timestamp' => '2025-01-01T10:30:00Z', 'action' => 'click' },
        { 'timestamp' => '2025-01-01T10:45:00Z', 'action' => 'click' }
      ]
    end
    let(:stats) do
      {
        total_actions: 3,
        unique_actions: 2,
        action_counts: { 'login' => 1, 'click' => 2 },
        first_activity: '2025-01-01T09:00:00Z',
        last_activity: '2025-01-01T10:45:00Z',
        most_frequent: 'click'
      }
    end
    let(:patterns) do
      [
        { 'pattern_type' => 'streak', 'description' => 'Daily login streak', 'confidence' => 0.9 }
      ]
    end
    let(:user_score) { 80.5 }
    let(:anomalies) do
      [
        { 'timestamp' => '2025-01-01T11:00:00Z', 'action' => 'delete', 'reason' => 'suspicious' }
      ]
    end

    before do
      allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
      allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
      allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
      allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
      allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
    end

    it 'returns an error report when no activities are found' do
      allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      result = reporter.generate_report(user_id)
      expect(result[:error]).to be true
      expect(result[:message]).to eq('No activities found')
      expect(result[:generated_at]).to be_a(String)
    end

    it 'builds a comprehensive report with default grouping (day)' do
      result = reporter.generate_report(user_id)
      expect(result[:user_id]).to eq(user_id)
      expect(result[:generated_at]).to be_a(String)

      expect(result[:summary][:total_actions]).to eq(3)
      expect(result[:summary][:unique_actions]).to eq(2)
      expect(result[:summary][:engagement_score]).to eq(user_score)
      expect(result[:summary][:first_activity]).to eq('2025-01-01T09:00:00Z')
      expect(result[:summary][:last_activity]).to eq('2025-01-01T10:45:00Z')

      expect(result[:action_breakdown]).to eq({ 'login' => 1, 'click' => 2 })

      expect(result[:patterns]).to eq([
                                        { type: 'streak', description: 'Daily login streak', confidence: 0.9 }
                                      ])

      expect(result[:anomalies]).to eq(anomalies)

      expect(result[:timeline]).to be_an(Array)
      expect(result[:timeline].size).to eq(1)
      expect(result[:timeline].first[:period]).to eq('2025-01-01')
      expect(result[:timeline].first[:total_actions]).to eq(3)
      expect(result[:timeline].first[:actions]).to eq({ 'login' => 1, 'click' => 2 })
      expect(result[:timeline].first[:first_timestamp]).to eq('2025-01-01T09:00:00Z')
      expect(result[:timeline].first[:last_timestamp]).to eq('2025-01-01T10:45:00Z')

      expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
      expect(result[:insights]).to include('1 anomalous activities detected - review recommended')
      expect(result[:insights].any? { |i| i.include?('Power user') }).to be false
    end

    it 'uses the provided group_by option to build the timeline' do
      result = reporter.generate_report(user_id, group_by: :hour)
      periods = result[:timeline].map { |e| e[:period] }
      expect(periods).to include('2025-01-01 09:00', '2025-01-01 10:00')
      ten_am_bucket = result[:timeline].find { |e| e[:period] == '2025-01-01 10:00' }
      expect(ten_am_bucket[:total_actions]).to eq(2)
      expect(ten_am_bucket[:actions]).to eq({ 'click' => 2 })
    end

    it 'generates insights based on metrics and patterns' do
      result = reporter.generate_report(user_id)
      expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
      expect(result[:insights]).not_to include('Diverse activity profile across multiple action types')
      expect(result[:insights]).not_to include('Clear behavioral patterns detected')
    end
  end

  describe '#format_timeline' do
    let(:activities) do
      [
        { 'timestamp' => '2025-01-01T09:00:00Z', 'action' => 'login' },
        { 'timestamp' => '2025-01-01T17:00:00Z', 'action' => 'click' },
        { 'timestamp' => '2025-01-02T10:00:00Z', 'action' => 'logout' },
        { 'timestamp' => '2025-01-02T10:30:00Z', 'action' => 'click' }
      ]
    end

    it 'returns empty array for no activities' do
      result = reporter.format_timeline([], :day)
      expect(result).to eq([])
    end

    it 'groups activities by hour' do
      result = reporter.format_timeline(activities, :hour)
      expect(result.map { |r| r[:period] }).to eq(['2025-01-01 09:00', '2025-01-01 17:00', '2025-01-02 10:00'])
      first = result.first
      expect(first[:total_actions]).to eq(1)
      expect(first[:actions]).to eq({ 'login' => 1 })
      expect(first[:first_timestamp]).to eq('2025-01-01T09:00:00Z')
      expect(first[:last_timestamp]).to eq('2025-01-01T09:00:00Z')
    end

    it 'groups activities by day' do
      result = reporter.format_timeline(activities, :day)
      expect(result.size).to eq(2)
      expect(result.first[:period]).to eq('2025-01-01')
      expect(result.first[:total_actions]).to eq(2)
      expect(result.first[:actions]).to eq({ 'login' => 1, 'click' => 1 })
      expect(result.first[:first_timestamp]).to eq('2025-01-01T09:00:00Z')
      expect(result.first[:last_timestamp]).to eq('2025-01-01T17:00:00Z')
    end

    it 'groups activities by week' do
      result = reporter.format_timeline(activities, :week)
      expect(result.size).to be >= 1
      expect(result.first[:period]).to match(/\A2025-W\d{2}\z/)
    end

    it 'groups activities by month' do
      result = reporter.format_timeline(activities, :month)
      expect(result.map { |r| r[:period] }).to eq(['2025-01'])
    end

    it 'falls back to day grouping for unknown group_by' do
      result = reporter.format_timeline(activities, :unknown)
      expect(result.size).to eq(2)
      expect(result.first[:period]).to eq('2025-01-01')
    end

    it 'handles invalid timestamps by using current time' do
      invalid = [{ 'timestamp' => 'not-a-time', 'action' => 'click' }]
      fixed_now = Time.utc(2025, 1, 0o2, 0o3, 0o4, 0o5)
      allow(Time).to receive(:now).and_return(fixed_now)
      result = reporter.format_timeline(invalid, :day)
      expect(result.size).to eq(1)
      expect(result.first[:period]).to eq('2025-01-02')
      expect(result.first[:actions]).to eq({ 'click' => 1 })
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 1,
        generated_at: '2025-01-01T00:00:00Z',
        summary: { total_actions: 2 },
        timeline: []
      }
    end

    it 'returns JSON data without writing to a file when no filepath is provided' do
      result = reporter.export_to_json(report)
      expect(result[:success]).to be true
      expect(result[:data]).to be_a(String)
      parsed = JSON.parse(result[:data])
      expect(parsed['user_id']).to eq(1)
      expect(parsed['summary']['total_actions']).to eq(2)
    end

    it 'writes JSON to the specified file and returns metadata' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(report, path)
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(path)
        expect(File.exist?(path)).to be true
        contents = File.read(path)
        expect(contents).to eq(JSON.pretty_generate(report))
        expect(result[:size]).to eq(contents.bytesize)
      end
    end

    it 'handles file write errors and returns an error hash' do
      allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      result = reporter.export_to_json(report, '/fake/path/report.json')
      expect(result[:success]).to be false
      expect(result[:error]).to eq('disk full')
    end
  end

  describe '#compare_users' do
    context 'with fewer than two users' do
      it 'returns an error report' do
        result = reporter.compare_users([1])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
      end
    end

    context 'with multiple users' do
      let(:user_ids) { [1, 2, 3] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(1).and_return([{ 'timestamp' => '2025-01-01T00:00:00Z',
                                                                                 'action' => 'a' }])
        allow(reporter).to receive(:fetch_user_activities).with(2).and_return([{ 'timestamp' => '2025-01-01T00:00:00Z',
                                                                                 'action' => 'b' }])
        allow(reporter).to receive(:fetch_user_activities).with(3).and_return([{ 'timestamp' => '2025-01-01T00:00:00Z',
                                                                                 'action' => 'c' }])

        allow(reporter).to receive(:fetch_activity_stats).with(1).and_return({ total_actions: 10, unique_actions: 3,
                                                                               action_counts: { 'a' => 10 }, first_activity: '2025-01-01T00:00:00Z', last_activity: '2025-01-01T23:00:00Z', most_frequent: 'a' })
        allow(reporter).to receive(:fetch_activity_stats).with(2).and_return({ total_actions: 20, unique_actions: 4,
                                                                               action_counts: { 'b' => 20 }, first_activity: '2025-01-01T00:00:00Z', last_activity: '2025-01-01T23:00:00Z', most_frequent: 'b' })
        allow(reporter).to receive(:fetch_activity_stats).with(3).and_return({ total_actions: 15, unique_actions: 5,
                                                                               action_counts: { 'c' => 15 }, first_activity: '2025-01-01T00:00:00Z', last_activity: '2025-01-01T23:00:00Z', most_frequent: 'c' })

        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2025-01-01T00:00:00Z',
                                                              'action' => 'a' }]).and_return(60.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2025-01-01T00:00:00Z',
                                                              'action' => 'b' }]).and_return(80.0)
        allow(reporter).to receive(:fetch_user_score).with([{ 'timestamp' => '2025-01-01T00:00:00Z',
                                                              'action' => 'c' }]).and_return(70.0)
      end

      it 'compares users and returns sorted comparisons with top user and average score' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq([2, 3, 1])
        expect(result[:comparisons].first[:engagement_score]).to eq(80.0)
        expect(result[:comparisons].first[:most_frequent_action]).to eq('b')
        expect(result[:top_user]).to eq(2)
        expect(result[:average_score]).to eq(70.0)
      end
    end
  end
end
