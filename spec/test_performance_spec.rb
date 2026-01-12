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
      instance_double('User', name: 'Alice', posts: posts1)
    end

    let(:user2) do
      instance_double('User', name: 'Bob', posts: posts2)
    end

    let(:posts1) do
      instance_double('ActiveRecord::Relation', count: 3)
    end

    let(:posts2) do
      instance_double('ActiveRecord::Relation', count: 5)
    end

    before do
      allow(User).to receive(:find).with(1).and_return(user1)
      allow(User).to receive(:find).with(2).and_return(user2)
    end

    context 'with valid user ids' do
      it 'queries each user and their posts and prints the report lines' do
        expect(User).to receive(:find).with(1).ordered.and_return(user1)
        expect(User).to receive(:find).with(2).ordered.and_return(user2)
        expect(user1).to receive(:posts).and_return(posts1)
        expect(user2).to receive(:posts).and_return(posts2)
        expect(posts1).to receive(:count).and_return(3)
        expect(posts2).to receive(:count).and_return(5)

        expect do
          report_generator.generate_user_report(user_ids)
        end.to output("Alice: 3 posts\nBob: 5 posts\n").to_stdout
      end
    end

    context 'with empty user_ids array' do
      let(:user_ids) do
        []
      end

      it 'does not query any users and outputs nothing' do
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
      let(:posts1) do
        instance_double('ActiveRecord::Relation', count: 0)
      end

      let(:user_ids) do
        [1]
      end

      it 'prints zero posts for that user' do
        expect(User).to receive(:find).with(1).and_return(user1)
        expect(user1).to receive(:posts).and_return(posts1)
        expect(posts1).to receive(:count).and_return(0)

        expect do
          report_generator.generate_user_report(user_ids)
        end.to output("Alice: 0 posts\n").to_stdout
      end
    end
  end

  describe '#build_csv' do
    let(:records) do
      []
    end

    context 'with multiple records' do
      let(:record1) do
        instance_double('Record', id: 1, name: 'Alice')
      end

      let(:record2) do
        instance_double('Record', id: 2, name: 'Bob')
      end

      let(:records) do
        [record1, record2]
      end

      it 'builds a CSV string with one line per record' do
        result = report_generator.build_csv(records)
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with empty records array' do
      it 'returns an empty string' do
        result = report_generator.build_csv(records)
        expect(result).to eq('')
      end
    end

    context 'with a single record' do
      let(:record) do
        instance_double('Record', id: 10, name: 'Charlie')
      end

      let(:records) do
        [record]
      end

      it 'returns CSV with a single line' do
        result = report_generator.build_csv(records)
        expect(result).to eq("10,Charlie\n")
      end
    end

    context 'when records contain objects missing expected methods' do
      let(:invalid_record) do
        Object.new
      end

      let(:records) do
        [invalid_record]
      end

      it 'raises a NoMethodError' do
        expect do
          report_generator.build_csv(records)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when records is nil' do
      it 'raises a NoMethodError when trying to iterate' do
        expect do
          report_generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping lists' do
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

      it 'includes duplicates when matches occur multiple times' do
        list_a = [1, 2, 2]
        list_b = [2, 2]
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to eq([2, 2, 2, 2])
      end
    end

    context 'with no overlapping elements' do
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

      it 'returns an empty array when list_a is empty' do
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to eq([])
      end

      it 'returns an empty array when list_b is empty' do
        result = report_generator.find_matches(list_b, list_a)
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

    context 'when lists contain different types' do
      let(:list_a) do
        [1, '2', :three]
      end

      let(:list_b) do
        ['2', :three, 4]
      end

      it 'matches using Ruby equality semantics' do
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to match_array(['2', :three])
      end
    end

    context 'when list arguments are nil' do
      it 'raises NoMethodError for nil list_a' do
        expect do
          report_generator.find_matches(nil, [])
        end.to raise_error(NoMethodError)
      end

      it 'raises NoMethodError for nil list_b' do
        expect do
          report_generator.find_matches([], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:user1) do
      instance_double('User', email: 'alice@example.com')
    end

    let(:user2) do
      instance_double('User', email: 'bob@example.com')
    end

    let(:users_relation) do
      [user1, user2]
    end

    before do
      allow(User).to receive(:all).and_return(users_relation)
      allow(report_generator).to receive(:send_email)
    end

    context 'when there are users to process' do
      it 'loads all users and sends an email to each' do
        expect(User).to receive(:all).and_return(users_relation)
        expect(report_generator).to receive(:send_email).with(user1)
        expect(report_generator).to receive(:send_email).with(user2)

        report_generator.process_all_users
      end
    end

    context 'when there are no users' do
      let(:users_relation) do
        []
      end

      it 'does not call send_email' do
        expect(User).to receive(:all).and_return(users_relation)
        expect(report_generator).not_to receive(:send_email)

        report_generator.process_all_users
      end
    end

    context 'when sending email raises an error' do
      before do
        allow(User).to receive(:all).and_return([user1])
        allow(report_generator).to receive(:send_email).with(user1).and_raise(StandardError.new('SMTP error'))
      end

      it 'propagates the error' do
        expect do
          report_generator.process_all_users
        end.to raise_error(StandardError, 'SMTP error')
      end
    end

    context 'when User.all raises an error' do
      before do
        allow(User).to receive(:all).and_raise(StandardError.new('DB error'))
      end

      it 'propagates the error from User.all' do
        expect do
          report_generator.process_all_users
        end.to raise_error(StandardError, 'DB error')
      end
    end
  end
end
