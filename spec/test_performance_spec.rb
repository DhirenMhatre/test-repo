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

      it 'does not query any users and prints nothing' do
        expect(User).not_to receive(:find)

        expect do
          report_generator.generate_user_report(user_ids)
        end.to output('').to_stdout
      end
    end

    context 'when a user id does not exist' do
      let(:user_ids) do
        [1]
      end

      before do
        allow(User).to receive(:find).with(1).and_raise(ActiveRecord::RecordNotFound)
      end

      it 'propagates the exception' do
        expect do
          report_generator.generate_user_report(user_ids)
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when user_ids is nil' do
      let(:user_ids) do
        nil
      end

      it 'raises a NoMethodError due to calling each on nil' do
        expect do
          report_generator.generate_user_report(user_ids)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    let(:records) do
      [
        double('Record', id: 1, name: 'Alice'),
        double('Record', id: 2, name: 'Bob')
      ]
    end

    context 'with multiple records' do
      it 'builds a CSV string with each record on its own line' do
        result = report_generator.build_csv(records)
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with a single record' do
      let(:records) do
        [
          double('Record', id: 10, name: 'Charlie')
        ]
      end

      it 'builds a CSV string with one line' do
        result = report_generator.build_csv(records)
        expect(result).to eq("10,Charlie\n")
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

    context 'when records is nil' do
      let(:records) do
        nil
      end

      it 'raises a NoMethodError due to calling each on nil' do
        expect do
          report_generator.build_csv(records)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when a record does not respond to id or name' do
      let(:records) do
        [
          Object.new
        ]
      end

      it 'raises a NoMethodError' do
        expect do
          report_generator.build_csv(records)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    let(:list_a) do
      [1, 2, 3, 2]
    end

    let(:list_b) do
      [2, 3, 4]
    end

    context 'with overlapping elements' do
      it 'returns all matches including duplicates based on nested loops' do
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to match_array([2, 2, 3])
        expect(result.count(2)).to eq(2)
        expect(result.count(3)).to eq(1)
      end
    end

    context 'with no overlapping elements' do
      let(:list_a) do
        [1, 5]
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

    context 'when list_a is nil' do
      let(:list_a) do
        nil
      end

      it 'raises a NoMethodError due to calling each on nil' do
        expect do
          report_generator.find_matches(list_a, list_b)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when list_b is nil' do
      let(:list_b) do
        nil
      end

      it 'raises a NoMethodError due to calling each on nil' do
        expect do
          report_generator.find_matches(list_a, list_b)
        end.to raise_error(NoMethodError)
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
      allow_any_instance_of(ReportGenerator).to receive(:send_email)
    end

    context 'when there are users returned by User.all' do
      it 'iterates over all users and calls send_email for each' do
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

      it 'does not call send_email' do
        expect(User).to receive(:all).and_return(users_relation)
        expect(report_generator).not_to receive(:send_email)

        report_generator.process_all_users
      end
    end

    context 'when User.all raises an error' do
      before do
        allow(User).to receive(:all).and_raise(StandardError.new('DB error'))
      end

      it 'propagates the exception' do
        expect do
          report_generator.process_all_users
        end.to raise_error(StandardError, 'DB error')
      end
    end
  end
end
