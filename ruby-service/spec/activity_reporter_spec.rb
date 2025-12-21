require 'spec_helper'
require 'time'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  describe '#initialize' do
    it 'sets default service URLs' do
      reporter = described_class.new
      expect(reporter.instance_variable_get(:@go_service_url)).to eq('http://localhost:8080')
      expect(reporter.instance_variable_get(:@python_service_url)).to eq('http://localhost:8081')
    end

    it 'sets custom service URLs when provided' do
      reporter = described_class.new(go_service_url: 'http://go', python_service_url: 'http://py')
      expect(reporter.instance_variable_get(:@go_service_url)).to eq('http://go')
      expect(reporter.instance_variable_get(:@python_service_url)).to eq('http://py')
    end
  end

  describe '#generate_report' do
    let(:reporter) do
      described_class.new
    end

    let(:fixed_time) do
      Time.utc(2025, 1, 1, 12, 0, 0)
    end

    before do
      allow(Time).to receive(:now).and_return(fixed_time)
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).and_return([])
      end

      it 'returns an error report' do
        result = reporter.generate_report('user-1')
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'when activities exist' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-01T10:00:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T11:30:00Z', 'action' => 'view' },
          { 'timestamp' => '2025-01-02T09:00:00Z', 'action' => 'purchase' }
        ]
      end

      let(:stats) do
        {
          total_actions: 3,
          unique_actions: 3,
          action_counts: { 'login' => 1, 'view' => 1, 'purchase' => 1 },
          first_activity: '2025-01-01T10:00:00Z',
          last_activity: '2025-01-02T09:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'daily', 'description' => 'Active in mornings', 'confidence' => 0.85 },
          { 'pattern_type' => 'conversion', 'description' => 'Purchases after viewing', 'confidence' => 0.7 }
        ]
      end

      let(:user_score) do
        76.5
      end

      let(:anomalies) do
        ['suspicious_login']
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('user-1').and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with('user-1').and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a complete report with expected keys and values' do
        result = reporter.generate_report('user-1')
        expect(result[:user_id]).to eq('user-1')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)

        expect(result[:summary][:total_actions]).to eq(3)
        expect(result[:summary][:unique_actions]).to eq(3)
        expect(result[:summary][:engagement_score]).to eq(76.5)
        expect(result[:summary][:first_activity]).to eq('2025-01-01T10:00:00Z')
        expect(result[:summary][:last_activity]).to eq('2025-01-02T09:00:00Z')

        expect(result[:action_breakdown]).to eq({ 'login' => 1, 'view' => 1, 'purchase' => 1 })

        expect(result[:patterns]).to eq([
                                          { type: 'daily', description: 'Active in mornings', confidence: 0.85 },
                                          { type: 'conversion', description: 'Purchases after viewing',
                                            confidence: 0.7 }
                                        ])

        expect(result[:anomalies]).to eq(['suspicious_login'])

        expect(result[:timeline]).to be_an(Array)
        expect(result[:timeline].length).to eq(2)
        days = result[:timeline].map { |t| t[:period] }
        expect(days).to eq(%w[2025-01-01 2025-01-02])

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights].any? { |i| i.include?('anomalous activities detected') }).to be true
      end

      it 'respects the group_by option for timeline' do
        result = reporter.generate_report('user-1', group_by: :day)
        days = result[:timeline].map { |t| t[:period] }
        expect(days).to eq(%w[2025-01-01 2025-01-02])

        result_hour = reporter.generate_report('user-1', group_by: :hour)
        hours = result_hour[:timeline].map { |t| t[:period] }
        expect(hours).to include('2025-01-01 10:00', '2025-01-01 11:00', '2025-01-02 09:00')
      end
    end
  end

  describe '#format_timeline' do
    let(:reporter) do
      described_class.new
    end

    let(:fixed_time) do
      Time.utc(2025, 2, 1, 0, 0, 0)
    end

    before do
      allow(Time).to receive(:now).and_return(fixed_time)
    end

    it 'returns an empty array when activities are empty' do
      result = reporter.format_timeline([])
      expect(result).to eq([])
    end

    it 'groups by hour correctly' do
      activities = [
        { 'timestamp' => '2025-01-01T13:15:00Z', 'action' => 'a' },
        { 'timestamp' => '2025-01-01T13:45:00Z', 'action' => 'b' },
        { 'timestamp' => '2025-01-01T14:05:00Z', 'action' => 'a' }
      ]
      result = reporter.format_timeline(activities, :hour)
      expect(result.length).to eq(2)
      expect(result[0][:period]).to eq('2025-01-01 13:00')
      expect(result[0][:total_actions]).to eq(2)
      expect(result[0][:actions]).to eq({ 'a' => 1, 'b' => 1 })
      expect(result[0][:first_timestamp]).to eq('2025-01-01T13:15:00Z')
      expect(result[0][:last_timestamp]).to eq('2025-01-01T13:45:00Z')
      expect(result[1][:period]).to eq('2025-01-01 14:00')
      expect(result[1][:total_actions]).to eq(1)
      expect(result[1][:actions]).to eq({ 'a' => 1 })
    end

    it 'groups by day correctly and sorts periods' do
      activities = [
        { 'timestamp' => '2025-01-02T10:00:00Z', 'action' => 'x' },
        { 'timestamp' => '2025-01-01T09:00:00Z', 'action' => 'y' }
      ]
      result = reporter.format_timeline(activities, :day)
      expect(result.map { |r| r[:period] }).to eq(%w[2025-01-01 2025-01-02])
      jan1 = result.find { |r| r[:period] == '2025-01-01' }
      jan2 = result.find { |r| r[:period] == '2025-01-02' }
      expect(jan1[:total_actions]).to eq(1)
      expect(jan1[:actions]).to eq({ 'y' => 1 })
      expect(jan2[:total_actions]).to eq(1)
      expect(jan2[:actions]).to eq({ 'x' => 1 })
    end

    it 'groups by week correctly' do
      activities = [
        { 'timestamp' => '2025-01-01T10:00:00Z', 'action' => 'a' },
        { 'timestamp' => '2025-01-03T12:00:00Z', 'action' => 'a' }
      ]
      period_str = Time.parse('2025-01-01T00:00:00Z').strftime('%Y-W%V')
      result = reporter.format_timeline(activities, :week)
      expect(result.length).to eq(1)
      expect(result.first[:period]).to eq(period_str)
      expect(result.first[:total_actions]).to eq(2)
      expect(result.first[:actions]).to eq({ 'a' => 2 })
    end

    it 'groups by month correctly' do
      activities = [
        { 'timestamp' => '2025-01-15T10:00:00Z', 'action' => 'a' },
        { 'timestamp' => '2025-02-01T11:00:00Z', 'action' => 'b' }
      ]
      result = reporter.format_timeline(activities, :month)
      expect(result.map { |r| r[:period] }).to eq(%w[2025-01 2025-02])
      jan = result.first
      feb = result.last
      expect(jan[:actions]).to eq({ 'a' => 1 })
      expect(feb[:actions]).to eq({ 'b' => 1 })
    end

    it 'falls back to current time when timestamp is invalid' do
      activities = [
        { 'timestamp' => 'not-a-date', 'action' => 'a' }
      ]
      result = reporter.format_timeline(activities, :day)
      expect(result.length).to eq(1)
      expect(result.first[:period]).to eq(fixed_time.strftime('%Y-%m-%d'))
    end
  end

  describe '#export_to_json' do
    let(:reporter) do
      described_class.new
    end

    let(:report_payload) do
      {
        user_id: 'user-xyz',
        generated_at: '2025-01-01T00:00:00Z',
        summary: { total_actions: 2, unique_actions: 2, engagement_score: 10.0, first_activity: 't1',
                   last_activity: 't2' },
        action_breakdown: { 'a' => 1, 'b' => 1 },
        patterns: [],
        anomalies: [],
        timeline: [],
        insights: []
      }
    end

    before do
      allow(reporter).to receive(:generate_report).and_return(report_payload)
    end

    it 'returns pretty JSON data when no filepath is provided' do
      result = reporter.export_to_json
      expect(result[:success]).to be true
      expect(result[:data]).to be_a(String)
      parsed = JSON.parse(result[:data])
      expect(parsed['user_id']).to eq('user-xyz')
      expect(parsed['summary']['total_actions']).to eq(2)
    end

    it 'writes JSON to the specified file path and returns metadata' do
      path = '/tmp/report.json'
      written_data = nil
      allow(File).to receive(:write) do |_fp, data|
        written_data = data
        123
      end
      result = reporter.export_to_json(report_payload, path)
      expect(result[:success]).to be true
      expect(result[:filepath]).to eq(path)
      expect(result[:size]).to eq(written_data.bytesize)
    end

    it 'handles file write errors gracefully' do
      allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      result = reporter.export_to_json(report_payload, '/tmp/fail.json')
      expect(result[:success]).to be false
      expect(result[:error]).to eq('disk full')
    end
  end

  describe '#compare_users' do
    let(:reporter) do
      described_class.new
    end

    let(:fixed_time) do
      Time.utc(2025, 1, 1, 0, 0, 0)
    end

    before do
      allow(Time).to receive(:now).and_return(fixed_time)
    end

    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['u1'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with two users' do
      let(:u1_activities) do
        [
          { 'timestamp' => '2025-01-01T10:00:00Z', 'action' => 'login' }
        ]
      end

      let(:u2_activities) do
        [
          { 'timestamp' => '2025-01-01T11:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2025-01-02T11:00:00Z', 'action' => 'view' }
        ]
      end

      let(:u1_stats) do
        {
          total_actions: 1,
          unique_actions: 1,
          action_counts: { 'login' => 1 },
          first_activity: '2025-01-01T10:00:00Z',
          last_activity: '2025-01-01T10:00:00Z',
          most_frequent: 'login'
        }
      end

      let(:u2_stats) do
        {
          total_actions: 2,
          unique_actions: 1,
          action_counts: { 'view' => 2 },
          first_activity: '2025-01-01T11:00:00Z',
          last_activity: '2025-01-02T11:00:00Z',
          most_frequent: 'view'
        }
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return(u1_activities)
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return(u2_activities)

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return(u1_stats)
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return(u2_stats)

        allow(reporter).to receive(:fetch_user_score).with(u1_activities).and_return(90.0)
        allow(reporter).to receive(:fetch_user_score).with(u2_activities).and_return(40.0)
      end

      it 'returns sorted comparisons by engagement score and computes summary fields' do
        result = reporter.compare_users(%w[u2 u1])
        expect(result[:total_users]).to eq(2)
        expect(result[:comparisons].length).to eq(2)

        # Sorted descending by engagement_score, so u1 first
        expect(result[:comparisons].first[:user_id]).to eq('u1')
        expect(result[:comparisons].first[:engagement_score]).to eq(90.0)
        expect(result[:comparisons].first[:total_actions]).to eq(1)
        expect(result[:comparisons].first[:most_frequent_action]).to eq('login')

        expect(result[:comparisons].last[:user_id]).to eq('u2')
        expect(result[:comparisons].last[:engagement_score]).to eq(40.0)
        expect(result[:comparisons].last[:total_actions]).to eq(2)
        expect(result[:comparisons].last[:most_frequent_action]).to eq('view')

        expect(result[:top_user]).to eq('u1')
        expect(result[:average_score]).to eq(((90.0 + 40.0) / 2.0).round(2))
      end
    end
  end
end
