require 'spec_helper'
require 'rails_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:report_generator) do
    described_class.new
  end

  describe '#generate_user_report' do
    let(:user_ids) do
      [1, 2]
    end

    let(:user1) do
      double('User', id: 1, name: 'Alice', posts: posts1)
    end

    let(:user2) do
      double('User', id: 2, name: 'Bob', posts: posts2)
    end

    let(:posts1) do
      double('PostsRelation1', count: 3)
    end

    let(:posts2) do
      double('PostsRelation2', count: 5)
    end

    before do
      allow(User).to receive(:find).with(1).and_return(user1)
      allow(User).to receive(:find).with(2).and_return(user2)
    end

    context 'with valid user ids' do
      it 'queries each user and their posts and prints the report lines' do
        expect(User).to receive(:find).with(1).and_return(user1)
        expect(User).to receive(:find).with(2).and_return(user2)
        expect(user1).to receive(:posts).and_return(posts1)
        expect(user2).to receive(:posts).and_return(posts2)
        expect(posts1).to receive(:count).and_return(3)
        expect(posts2).to receive(:count).and_return(5)

        expect do
          report_generator.generate_user_report(user_ids)
        end.to output("Alice: 3 posts\nBob: 5 posts\n").to_stdout
      end
    end

    context 'with an empty array of user ids' do
      let(:user_ids) do
        []
      end

      it 'does not query any users and does not print anything' do
        expect(User).not_to receive(:find)
        expect do
          report_generator.generate_user_report(user_ids)
        end.to output('').to_stdout
      end
    end

    context 'when User.find raises an error' do
      before do
        allow(User).to receive(:find).with(1).and_raise(ActiveRecord::RecordNotFound)
      end

      it 'propagates the error' do
        expect do
          report_generator.generate_user_report([1])
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when user has no posts' do
      let(:user_ids) do
        [3]
      end

      let(:user3) do
        double('User', id: 3, name: 'Charlie', posts: posts3)
      end

      let(:posts3) do
        double('PostsRelation3', count: 0)
      end

      before do
        allow(User).to receive(:find).with(3).and_return(user3)
      end

      it 'prints zero posts for that user' do
        expect do
          report_generator.generate_user_report(user_ids)
        end.to output("Charlie: 0 posts\n").to_stdout
      end
    end
  end

  describe '#build_csv' do
    let(:record1) do
      double('Record', id: 1, name: 'Alice')
    end

    let(:record2) do
      double('Record', id: 2, name: 'Bob')
    end

    let(:records) do
      [record1, record2]
    end

    context 'with multiple records' do
      it 'builds a CSV string with one line per record' do
        result = report_generator.build_csv(records)
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with an empty array' do
      let(:records) do
        []
      end

      it 'returns an empty string' do
        result = report_generator.build_csv(records)
        expect(result).to eq('')
      end
    end

    context 'with a single record' do
      let(:records) do
        [record1]
      end

      it 'returns a CSV string with one line' do
        result = report_generator.build_csv(records)
        expect(result).to eq("1,Alice\n")
      end
    end

    context 'when records contain nil values' do
      let(:records) do
        [nil]
      end

      it 'raises a NoMethodError when trying to access id on nil' do
        expect do
          report_generator.build_csv(records)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'when there are common elements' do
      let(:list_a) do
        [1, 2, 3]
      end

      let(:list_b) do
        [2, 3, 4]
      end

      it 'returns the matching elements' do
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to match_array([2, 3])
      end

      it 'includes duplicates when elements appear multiple times' do
        list_a = [1, 2, 2, 3]
        list_b = [2, 2, 4]
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to eq([2, 2, 2, 2])
      end
    end

    context 'when there are no common elements' do
      let(:list_a) do
        [1, 5, 6]
      end

      let(:list_b) do
        [2, 3, 4]
      end

      it 'returns an empty array' do
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to eq([])
      end
    end

    context 'when one list is empty' do
      let(:list_a) do
        []
      end

      let(:list_b) do
        [1, 2, 3]
      end

      it 'returns an empty array' do
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to eq([])
      end
    end

    context 'when both lists are empty' do
      let(:list_a) do
        []
      end

      let(:list_b) do
        []
      end

      it 'returns an empty array' do
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to eq([])
      end
    end

    context 'when lists contain non-numeric elements' do
      let(:list_a) do
        %w[a b c]
      end

      let(:list_b) do
        %w[b c d]
      end

      it 'returns matching string elements' do
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to match_array(%w[b c])
      end
    end

    context 'when lists contain nil values' do
      let(:list_a) do
        [nil, 1, 2]
      end

      let(:list_b) do
        [nil, 2, 3]
      end

      it 'treats nil as a comparable element' do
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to match_array([nil, 2])
      end
    end
  end

  describe '#process_all_users' do
    let(:user1) do
      double('User', id: 1, email: 'alice@example.com')
    end

    let(:user2) do
      double('User', id: 2, email: 'bob@example.com')
    end

    let(:users_relation) do
      [user1, user2]
    end

    before do
      allow(User).to receive(:all).and_return(users_relation)
      allow(report_generator).to receive(:send_email)
    end

    context 'when there are users returned by User.all' do
      it 'iterates over all users and sends an email to each' do
        expect(User).to receive(:all).and_return(users_relation)
        expect(report_generator).to receive(:send_email).with(user1)
        expect(report_generator).to receive(:send_email).with(user2)

        report_generator.process_all_users
      end
    end

    context 'when User.all returns an empty collection' do
      let(:users_relation) do
        []
      end

      it 'does not attempt to send any emails' do
        expect(report_generator).not_to receive(:send_email)
        report_generator.process_all_users
      end
    end

    context 'when sending email raises an error for a user' do
      before do
        allow(report_generator).to receive(:send_email).with(user1).and_raise(StandardError, 'SMTP error')
      end

      it 'propagates the error and stops processing' do
        expect do
          report_generator.process_all_users
        end.to raise_error(StandardError, 'SMTP error')
      end
    end

    context 'when User.all raises an error' do
      before do
        allow(User).to receive(:all).and_raise(StandardError, 'DB error')
      end

      it 'propagates the error' do
        expect do
          report_generator.process_all_users
        end.to raise_error(StandardError, 'DB error')
      end
    end
  end
end
