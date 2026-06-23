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
      it 'queries each user by id' do
        expect(User).to receive(:find).with(1).ordered.and_return(user1)
        expect(User).to receive(:find).with(2).ordered.and_return(user2)

        report_generator.generate_user_report(user_ids)
      end

      it 'accesses posts for each user' do
        expect(user1).to receive(:posts).and_return(posts1)
        expect(user2).to receive(:posts).and_return(posts2)

        report_generator.generate_user_report(user_ids)
      end

      it 'prints a line for each user with post count' do
        expect do
          report_generator.generate_user_report(user_ids)
        end.to output("Alice: 3 posts\nBob: 5 posts\n").to_stdout
      end
    end

    context 'with empty user_ids' do
      let(:user_ids) do
        []
      end

      it 'does not query any users' do
        expect(User).not_to receive(:find)
        expect do
          report_generator.generate_user_report(user_ids)
        end.not_to output.to_stdout
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
  end

  describe '#build_csv' do
    let(:record1) do
      double('Record', id: 1, name: 'Alice')
    end

    let(:record2) do
      double('Record', id: 2, name: 'Bob')
    end

    context 'with multiple records' do
      let(:records) do
        [record1, record2]
      end

      it 'returns a CSV string with one line per record' do
        result = report_generator.build_csv(records)
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with a single record' do
      let(:records) do
        [record1]
      end

      it 'returns CSV with a single line' do
        result = report_generator.build_csv(records)
        expect(result).to eq("1,Alice\n")
      end
    end

    context 'with empty records' do
      let(:records) do
        []
      end

      it 'returns an empty string' do
        result = report_generator.build_csv(records)
        expect(result).to eq('')
      end
    end

    context 'with records having nil attributes' do
      let(:record_with_nil) do
        double('Record', id: nil, name: nil)
      end

      let(:records) do
        [record_with_nil]
      end

      it 'converts nil attributes to empty strings in interpolation' do
        result = report_generator.build_csv(records)
        expect(result).to eq(",\n")
      end
    end

    context 'when records is nil' do
      it 'raises NoMethodError when trying to iterate' do
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

      it 'returns items that appear in both lists' do
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to match_array([2, 3])
      end

      it 'includes duplicates when they appear multiple times in list_b' do
        list_b_with_duplicates = [2, 2, 3]
        result = report_generator.find_matches(list_a, list_b_with_duplicates)
        expect(result).to eq([2, 2, 3])
      end

      it 'includes duplicates when they appear multiple times in list_a' do
        list_a_with_duplicates = [2, 2, 3]
        result = report_generator.find_matches(list_a_with_duplicates, list_b)
        expect(result).to eq([2, 2, 3])
      end
    end

    context 'with no overlap' do
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
      it 'returns empty when list_a is empty' do
        result = report_generator.find_matches([], [1, 2, 3])
        expect(result).to eq([])
      end

      it 'returns empty when list_b is empty' do
        result = report_generator.find_matches([1, 2, 3], [])
        expect(result).to eq([])
      end
    end

    context 'when both lists are empty' do
      it 'returns an empty array' do
        result = report_generator.find_matches([], [])
        expect(result).to eq([])
      end
    end

    context 'with non-numeric items' do
      it 'matches strings correctly' do
        list_a = %w[a b c]
        list_b = %w[b c d]
        result = report_generator.find_matches(list_a, list_b)
        expect(result).to match_array(%w[b c])
      end

      it 'uses == for comparison semantics' do
        obj1 = double('Obj1')
        obj2 = double('Obj2')
        allow(obj1).to receive(:==).with(obj2).and_return(true)
        allow(obj2).to receive(:==).with(obj1).and_return(false)

        result = report_generator.find_matches([obj1], [obj2])
        expect(result).to eq([obj1])
      end
    end

    context 'when list_a is nil' do
      it 'raises NoMethodError when trying to iterate' do
        expect do
          report_generator.find_matches(nil, [1, 2])
        end.to raise_error(NoMethodError)
      end
    end

    context 'when list_b is nil' do
      it 'raises NoMethodError when trying to iterate' do
        expect do
          report_generator.find_matches([1, 2], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:user1) do
      double('User', id: 1)
    end

    let(:user2) do
      double('User', id: 2)
    end

    before do
      allow(User).to receive(:all).and_return([user1, user2])
      allow(report_generator).to receive(:send_email)
    end

    it 'loads all users via User.all' do
      expect(User).to receive(:all).and_return([user1, user2])
      report_generator.process_all_users
    end

    it 'sends an email to each user' do
      expect(report_generator).to receive(:send_email).with(user1).ordered
      expect(report_generator).to receive(:send_email).with(user2).ordered

      report_generator.process_all_users
    end

    context 'when there are no users' do
      before do
        allow(User).to receive(:all).and_return([])
      end

      it 'does not call send_email' do
        expect(report_generator).not_to receive(:send_email)
        report_generator.process_all_users
      end
    end

    context 'when send_email raises an error for a user' do
      before do
        allow(report_generator).to receive(:send_email).with(user1).and_raise(StandardError, 'email failed')
      end

      it 'propagates the error and stops processing' do
        expect do
          report_generator.process_all_users
        end.to raise_error(StandardError, 'email failed')
      end
    end
  end
end
