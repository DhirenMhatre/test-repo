require 'spec_helper'
require 'json'
require 'time'
require 'rails_helper'
require_relative '../app/activity_reporter'

RSpec.describe ActivityReporter do
  let(:reporter) do
    described_class.new(
      go_service_url: 'http://localhost:8080',
      python_service_url: 'http://localhost:8081'
    )
  end

  describe '#generate_report' do
    let(:user_id) { 'user-123' }
    let(:fixed_now) { Time.parse('2024-01-01T12:00:00Z') }

    before do
      allow(Time).to receive(:now).and_return(fixed_now)
    end

    context 'when no activities are found' do
      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return([])
      end

      it 'returns an error report with the correct message' do
        result = reporter.generate_report(user_id)
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('No activities found')
        expect(result[:generated_at]).to eq(fixed_now.iso8601)
      end
    end

    context 'when activities exist' do
      let(:activities) do
        [
          { 'timestamp' => '2023-01-01T10:00:00Z', 'action' => 'click' },
          { 'timestamp' => '2023-01-01T11:00:00Z', 'action' => 'view' },
          { 'timestamp' => '2023-01-02T09:00:00Z', 'action' => 'click' }
        ]
      end

      let(:stats) do
        {
          total_actions: 150,
          unique_actions: 11,
          action_counts: { 'click' => 100, 'view' => 50 },
          first_activity: '2023-01-01T10:00:00Z',
          last_activity: '2023-01-02T09:00:00Z',
          most_frequent: 'click'
        }
      end

      let(:patterns_raw) do
        [
          { 'pattern_type' => 'sequence', 'description' => 'click after view', 'confidence' => 0.9 },
          { 'pattern_type' => 'time_of_day', 'description' => 'morning activity', 'confidence' => 0.8 },
          { 'pattern_type' => 'frequency', 'description' => 'daily usage', 'confidence' => 0.85 }
        ]
      end

      let(:user_score) { 80.5 }
      let(:anomalies) { %w[suspicious_login rapid_clicks] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with(user_id).and_return(activities)
        allow(reporter).to receive(:fetch_activity_stats).with(user_id).and_return(stats)
        allow(reporter).to receive(:fetch_activity_patterns).with(activities).and_return(patterns_raw)
        allow(reporter).to receive(:fetch_user_score).with(activities).and_return(user_score)
        allow(reporter).to receive(:fetch_anomalies).with(activities).and_return(anomalies)
      end

      it 'builds a comprehensive report with summary, patterns, anomalies, timeline, and insights' do
        result = reporter.generate_report(user_id, group_by: :day)
        expect(result[:user_id]).to eq(user_id)
        expect(result[:generated_at]).to eq(fixed_now.iso8601)

        expect(result[:summary][:total_actions]).to eq(stats[:total_actions])
        expect(result[:summary][:unique_actions]).to eq(stats[:unique_actions])
        expect(result[:summary][:engagement_score]).to eq(user_score)
        expect(result[:summary][:first_activity]).to eq(stats[:first_activity])
        expect(result[:summary][:last_activity]).to eq(stats[:last_activity])

        expect(result[:action_breakdown]).to eq(stats[:action_counts])

        expect(result[:patterns]).to contain_exactly(
          { type: 'sequence', description: 'click after view', confidence: 0.9 },
          { type: 'time_of_day', description: 'morning activity', confidence: 0.8 },
          { type: 'frequency', description: 'daily usage', confidence: 0.85 }
        )

        expect(result[:anomalies]).to eq(anomalies)

        expect(result[:timeline].size).to eq(2)
        expect(result[:timeline]).to include(
          a_hash_including(
            period: '2023-01-01',
            total_actions: 2,
            actions: { 'click' => 1, 'view' => 1 },
            first_timestamp: '2023-01-01T10:00:00Z',
            last_timestamp: '2023-01-01T11:00:00Z'
          )
        )
        expect(result[:timeline]).to include(
          a_hash_including(
            period: '2023-01-02',
            total_actions: 1,
            actions: { 'click' => 1 },
            first_timestamp: '2023-01-02T09:00:00Z',
            last_timestamp: '2023-01-02T09:00:00Z'
          )
        )

        expect(result[:insights]).to include('Highly engaged user with strong activity patterns')
        expect(result[:insights]).to include('Diverse activity profile across multiple action types')
        expect(result[:insights]).to include('Clear behavioral patterns detected')
        expect(result[:insights]).to include('2 anomalous activities detected - review recommended')
        expect(result[:insights]).to include('Power user - high volume of activities')
      end
    end
  end

  describe '#format_timeline' do
    let(:activities) do
      [
        { 'timestamp' => '2023-02-01T10:15:00Z', 'action' => 'click' },
        { 'timestamp' => '2023-02-01T10:45:00Z', 'action' => 'view' },
        { 'timestamp' => '2023-02-01T11:00:00Z', 'action' => 'click' },
        { 'timestamp' => '2023-02-02T12:00:00Z', 'action' => 'share' }
      ]
    end

    it 'returns empty array when activities are empty' do
      expect(reporter.format_timeline([])).to eq([])
    end

    it 'groups by day by default' do
      timeline = reporter.format_timeline(activities, :day)
      expect(timeline.size).to eq(2)

      day1 = timeline.find { |e| e[:period] == '2023-02-01' }
      expect(day1[:total_actions]).to eq(3)
      expect(day1[:actions]).to eq({ 'click' => 2, 'view' => 1 })
      expect(day1[:first_timestamp]).to eq('2023-02-01T10:15:00Z')
      expect(day1[:last_timestamp]).to eq('2023-02-01T11:00:00Z')

      day2 = timeline.find { |e| e[:period] == '2023-02-02' }
      expect(day2[:total_actions]).to eq(1)
      expect(day2[:actions]).to eq({ 'share' => 1 })
      expect(day2[:first_timestamp]).to eq('2023-02-02T12:00:00Z')
      expect(day2[:last_timestamp]).to eq('2023-02-02T12:00:00Z')
    end

    it 'groups by hour' do
      timeline = reporter.format_timeline(activities, :hour)
      expect(timeline.size).to eq(3)
      expect(timeline).to include(a_hash_including(period: '2023-02-01 10:00', total_actions: 2))
      expect(timeline).to include(a_hash_including(period: '2023-02-01 11:00', total_actions: 1))
      expect(timeline).to include(a_hash_including(period: '2023-02-02 12:00', total_actions: 1))
    end

    it 'groups by week' do
      acts = [
        { 'timestamp' => '2023-01-02T00:00:00Z', 'action' => 'a' },
        { 'timestamp' => '2023-01-09T00:00:00Z', 'action' => 'b' }
      ]
      week1 = Time.parse('2023-01-02T00:00:00Z').strftime('%Y-W%V')
      week2 = Time.parse('2023-01-09T00:00:00Z').strftime('%Y-W%V')
      timeline = reporter.format_timeline(acts, :week)
      expect(timeline).to include(a_hash_including(period: week1, total_actions: 1))
      expect(timeline).to include(a_hash_including(period: week2, total_actions: 1))
    end

    it 'groups by month' do
      acts = [
        { 'timestamp' => '2023-03-01T00:00:00Z', 'action' => 'a' },
        { 'timestamp' => '2023-03-15T00:00:00Z', 'action' => 'b' },
        { 'timestamp' => '2023-04-01T00:00:00Z', 'action' => 'c' }
      ]
      timeline = reporter.format_timeline(acts, :month)
      expect(timeline).to include(a_hash_including(period: '2023-03', total_actions: 2,
                                                   actions: { 'a' => 1, 'b' => 1 }))
      expect(timeline).to include(a_hash_including(period: '2023-04', total_actions: 1, actions: { 'c' => 1 }))
    end

    it 'handles invalid timestamps by using current time' do
      fixed_now = Time.parse('2023-05-05T05:05:05Z')
      allow(Time).to receive(:now).and_return(fixed_now)
      acts = [
        { 'timestamp' => 'invalid-timestamp', 'action' => 'x' }
      ]
      timeline = reporter.format_timeline(acts, :day)
      expect(timeline.size).to eq(1)
      expect(timeline.first[:period]).to eq(fixed_now.strftime('%Y-%m-%d'))
      expect(timeline.first[:total_actions]).to eq(1)
      expect(timeline.first[:actions]).to eq({ 'x' => 1 })
    end

    it 'sorts timeline by period ascending' do
      acts = [
        { 'timestamp' => '2023-01-02T01:00:00Z', 'action' => 'b' },
        { 'timestamp' => '2023-01-01T01:00:00Z', 'action' => 'a' }
      ]
      timeline = reporter.format_timeline(acts, :day)
      expect(timeline.map { |e| e[:period] }).to eq(%w[2023-01-01 2023-01-02])
    end
  end

  describe '#export_to_json' do
    let(:report) do
      {
        user_id: 'user-1',
        summary: { total_actions: 3 }
      }
    end

    it 'returns pretty JSON data when filepath is not provided' do
      result = reporter.export_to_json(report)
      expect(result[:success]).to eq(true)
      expect(result[:data]).to eq(JSON.pretty_generate(report))
      expect(result).not_to have_key(:filepath)
    end

    it 'writes pretty JSON to the given filepath and returns metadata' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'report.json')
        result = reporter.export_to_json(report, path)
        expect(result[:success]).to eq(true)
        expect(result[:filepath]).to eq(path)
        expect(result[:size]).to eq(JSON.pretty_generate(report).bytesize)
        written = File.read(path)
        expect(written).to eq(JSON.pretty_generate(report))
      end
    end

    it 'returns an error hash when writing fails' do
      allow(File).to receive(:write).and_raise(StandardError.new('disk full'))
      result = reporter.export_to_json(report, '/unwritable/path/report.json')
      expect(result[:success]).to eq(false)
      expect(result[:error]).to eq('disk full')
    end
  end

  describe '#compare_users' do
    context 'when less than two users are provided' do
      it 'returns an error report' do
        result = reporter.compare_users(['only-one'])
        expect(result[:error]).to eq(true)
        expect(result[:message]).to eq('At least 2 users required')
      end
    end

    context 'with multiple users' do
      let(:user_ids) { %w[u1 u2 u3] }
      let(:u1_activities) { [{ 'timestamp' => '2023-01-01T00:00:00Z', 'action' => 'a' }] }
      let(:u2_activities) { [{ 'timestamp' => '2023-01-02T00:00:00Z', 'action' => 'b' }] }
      let(:u3_activities) { [{ 'timestamp' => '2023-01-03T00:00:00Z', 'action' => 'c' }] }

      before do
        allow(reporter).to receive(:fetch_user_activities).with('u1').and_return(u1_activities)
        allow(reporter).to receive(:fetch_user_activities).with('u2').and_return(u2_activities)
        allow(reporter).to receive(:fetch_user_activities).with('u3').and_return(u3_activities)

        allow(reporter).to receive(:fetch_activity_stats).with('u1').and_return({ total_actions: 10, unique_actions: 2,
                                                                                  action_counts: {}, first_activity: '', last_activity: '', most_frequent: 'a' })
        allow(reporter).to receive(:fetch_activity_stats).with('u2').and_return({ total_actions: 20, unique_actions: 3,
                                                                                  action_counts: {}, first_activity: '', last_activity: '', most_frequent: 'b' })
        allow(reporter).to receive(:fetch_activity_stats).with('u3').and_return({ total_actions: 15, unique_actions: 1,
                                                                                  action_counts: {}, first_activity: '', last_activity: '', most_frequent: 'c' })

        allow(reporter).to receive(:fetch_user_score).with(u1_activities).and_return(55.0)
        allow(reporter).to receive(:fetch_user_score).with(u2_activities).and_return(92.3)
        allow(reporter).to receive(:fetch_user_score).with(u3_activities).and_return(70.7)
      end

      it 'returns comparisons sorted by engagement_score descending with correct top_user and average_score' do
        result = reporter.compare_users(user_ids)
        expect(result[:total_users]).to eq(3)
        expect(result[:comparisons].map { |c| c[:user_id] }).to eq(%w[u2 u3 u1])

        top = result[:comparisons].first
        expect(result[:top_user]).to eq(top[:user_id])
        expect(top[:user_id]).to eq('u2')
        expect(top[:total_actions]).to eq(20)
        expect(top[:engagement_score]).to eq(92.3)
        expect(top[:most_frequent_action]).to eq('b')

        avg = ((92.3 + 70.7 + 55.0) / 3.0).round(2)
        expect(result[:average_score]).to eq(avg)
      end

      it 'invokes the underlying data fetch methods for each user' do
        expect(reporter).to receive(:fetch_user_activities).with('u1').and_return(u1_activities)
        expect(reporter).to receive(:fetch_user_activities).with('u2').and_return(u2_activities)
        expect(reporter).to receive(:fetch_user_activities).with('u3').and_return(u3_activities)

        expect(reporter).to receive(:fetch_activity_stats).with('u1').and_return({ total_actions: 10, unique_actions: 2,
                                                                                   action_counts: {}, first_activity: '', last_activity: '', most_frequent: 'a' })
        expect(reporter).to receive(:fetch_activity_stats).with('u2').and_return({ total_actions: 20, unique_actions: 3,
                                                                                   action_counts: {}, first_activity: '', last_activity: '', most_frequent: 'b' })
        expect(reporter).to receive(:fetch_activity_stats).with('u3').and_return({ total_actions: 15, unique_actions: 1,
                                                                                   action_counts: {}, first_activity: '', last_activity: '', most_frequent: 'c' })

        allow(reporter).to receive(:fetch_user_score).and_return(55.0, 92.3, 70.7)

        reporter.compare_users(user_ids)
      end
    end
  end
end
