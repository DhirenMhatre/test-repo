require 'spec_helper'
require 'json'
require 'time'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new
  end

  let(:fixed_time) do
    Time.parse('2025-01-01T12:00:00Z')
  end

  before do
    allow(Time).to receive(:now).and_return(fixed_time)
  end

  describe '#generate_report' do
    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([])
      end

      it 'returns an error report with message and timestamp' do
        result = reporter.generate_report('u1')
        expect(result[:error]).to be true
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with activities and options' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-01T10:30:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T11:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-02T09:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-08T09:15:00Z', 'action' => 'purchase' }
        ]
      end

      let(:stats) do
        {
          total_actions: 105,
          unique_actions: 3,
          action_counts: { 'login' => 2, 'click' => 1, 'purchase' => 1 },
          first_activity: '2025-01-01T10:30:00Z',
          last_activity: '2025-01-08T09:15:00Z',
          most_frequent: 'login'
        }
      end

      let(:patterns) do
        [
          { 'pattern_type' => 'sequence', 'description' => 'Login then click', 'confidence' => 0.8 },
          { 'pattern_type' => 'time_of_day', 'description' => 'Morning activity', 'confidence' => 0.7 },
          { 'pattern_type' => 'weekly', 'description' => 'Wednesday spikes', 'confidence' => 0.6 }
        ]
      end

      let(:anomalies) do
        [
          { 'id' => 1, 'note' => 'suspicious' }
        ]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(82.5)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a comprehensive report with weekly grouping' do
        result = reporter.generate_report('u1', group_by: :week)
        expect(result[:user_id]).to eq('u1')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)

        expect(result[:summary][:total_actions]).to eq(105)
        expect(result[:summary][:unique_actions]).to eq(3)
        expect(result[:summary][:engagement_score]).to eq(82.5)
        expect(result[:summary][:first_activity]).to eq('2025-01-01T10:30:00Z')
        expect(result[:summary][:last_activity]).to eq('2025-01-08T09:15:00Z')

        expect(result[:action_breakdown]).to eq({ 'login' => 2, 'click' => 1, 'purchase' => 1 })

        expect(result[:patterns]).to include(
          { type: 'sequence', description: 'Login then click', confidence: 0.8 },
          { type: 'time_of_day', description: 'Morning activity', confidence: 0.7 },
          { type: 'weekly', description: 'Wednesday spikes', confidence: 0.6 }
        )

        expect(result[:anomalies]).to eq(anomalies)

        expect(result[:timeline]).to be_an(Array)
        periods = result[:timeline].map do |e|
          e[:period]
        end
        expect(periods).to eq(%w[2025-W01 2025-W02])

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('1 anomalous activities detected - review recommended')
        expect(result[:insights]).to include('Power user - high volume of activities')
        expect(result[:insights]).not_to include('Diverse activity profile across multiple action types')
      end

      it 'defaults to daily grouping when group_by is not provided' do
        result = reporter.generate_report('u1')
        periods = result[:timeline].map do |e|
          e[:period]
        end
        expect(periods).to eq(%w[2025-01-01 2025-01-02 2025-01-08])
      end
    end
  end

  describe '#format_timeline' do
    context 'with empty activities' do
      it 'returns an empty array' do
        result = reporter.format_timeline([])
        expect(result).to eq([])
      end
    end

    context 'with invalid and valid timestamps grouped by hour' do
      let(:activities) do
        [
          { 'timestamp' => 'not-a-time', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T12:15:00Z', 'action' => 'login' },
          { 'timestamp' => '2025-01-01T12:45:00Z', 'action' => 'click' },
          { 'timestamp' => '2025-01-01T13:00:00Z', 'action' => 'login' }
        ]
      end

      it 'groups into hours and falls back to current time on parse errors' do
        result = reporter.format_timeline(activities, :hour)
        periods = result.map do |e|
          e[:period]
        end
        expect(periods).to eq(['2025-01-01 12:00', '2025-01-01 13:00'])
        first_bucket = result.find do |e|
          e[:period] == '2025-01-01 12:00'
        end
        expect(first_bucket[:total_actions]).to eq(3)
        expect(first_bucket[:actions]['login']).to eq(2)
        expect(first_bucket[:actions]['click']).to eq(1)
        expect(first_bucket[:first_timestamp]).to eq('not-a-time')
        expect(first_bucket[:last_timestamp]).to eq('2025-01-01T12:45:00Z')
      end
    end

    context 'with month grouping' do
      let(:activities) do
        [
          { 'timestamp' => '2025-01-15T00:00:00Z', 'action' => 'a' },
          { 'timestamp' => '2025-01-31T23:59:59Z', 'action' => 'b' },
          { 'timestamp' => '2025-02-01T00:00:00Z', 'action' => 'a' }
        ]
      end

      it 'groups by month and sorts periods' do
        result = reporter.format_timeline(activities, :month)
        periods = result.map do |e|
          e[:period]
        end
        expect(periods).to eq(%w[2025-01 2025-02])
        jan = result.first
        expect(jan[:total_actions]).to eq(2)
        expect(jan[:actions]['a']).to eq(1)
        expect(jan[:actions]['b']).to eq(1)
        expect(jan[:first_timestamp]).to eq('2025-01-15T00:00:00Z')
        expect(jan[:last_timestamp]).to eq('2025-01-31T23:59:59Z')
      end
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 'u1',
        summary: { total_actions: 2 },
        timeline: []
      }
    end

    context 'when filepath is not provided' do
      it 'returns pretty JSON data and success' do
        result = reporter.export_to_json(report)
        expect(result[:success]).to be true
        json = result[:data]
        parsed = JSON.parse(json)
        expect(parsed['user_id']).to eq('u1')
        expect(parsed['summary']['total_actions']).to eq(2)
      end
    end

    context 'when filepath is provided' do
      it 'writes the file and returns metadata' do
        filepath = '/tmp/report.json'
        expect(File).to receive(:write).with(filepath, kind_of(String)).and_return(123)
        result = reporter.export_to_json(report, filepath)
        expect(result[:success]).to be true
        expect(result[:filepath]).to eq(filepath)
        expect(result[:size]).to be > 0
      end
    end

    context 'when file write raises an error' do
      it 'returns a failure with error message' do
        filepath = '/tmp/report.json'
        allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
        result = reporter.export_to_json(report, filepath)
        expect(result[:success]).to be false
        expect(result[:error]).to include('disk full')
      end
    end
  end

  describe '#compare_users' do
    context 'when fewer than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['u1'])
        expect(result[:error]).to be true
        expect(result[:message]).to eq('At least 2 users required')
        expect(result[:generated_at]).to eq(fixed_time.iso8601)
      end
    end

    context 'with multiple users' do
      let(:user_ids) do
        %w[u1 u2 u3]
      end

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return([{
                                                                                   'timestamp' => '2025-01-01T00:00:00Z', 'action' => 'a'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return([{
                                                                                   'timestamp' => '2025-01-01T01:00:00Z', 'action' => 'b'
                                                                                 }])
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return([{
                                                                                   'timestamp' => '2025-01-01T02:00:00Z', 'action' => 'c'
                                                                                 }])

        stats1 = { total_actions: 10, unique_actions: 2, action_counts: { 'a' => 10 },
                   first_activity: '2025-01-01T00:00:00Z', last_activity: '2025-01-01T00:00:00Z', most_frequent: 'a' }
        stats2 = { total_actions: 3, unique_actions: 1, action_counts: { 'b' => 3 },
                   first_activity: '2025-01-01T01:00:00Z', last_activity: '2025-01-01T01:00:00Z', most_frequent: 'b' }
        stats3 = { total_actions: 20, unique_actions: 3, action_counts: { 'c' => 20 },
                   first_activity: '2025-01-01T02:00:00Z', last_activity: '2025-01-01T02:00:00Z', most_frequent: 'c' }
        allow(reporter).to receive(:fetch_activity_stats).and_return(stats1, stats2, stats3)
        allow(reporter).to receive(:fetch_user_score).and_return(80.0, 50.0, 90.0)
      end

      it 'returns sorted comparisons, top user, and average score' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        ids = result[:comparisons].map do |c|
          c[:user_id]
        end
        expect(ids).to eq(%w[u3 u1 u2])
        expect(result[:comparisons].first[:engagement_score]).to eq(90.0)
        expect(result[:comparisons].first[:most_frequent_action]).to eq('c')
        expect(result[:top_user]).to eq('u3')
        expect(result[:average_score]).to eq(((80.0 + 50.0 + 90.0) / 3.0).round(2))
      end
    end
  end
end
