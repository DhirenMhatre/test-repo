require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:instance) do
    described_class.new
  end

  describe '#generate_user_report' do
    before do
      stub_const('User', Class.new)
    end

    context 'with valid user_ids' do
      let(:user_ids) do
        [101, 202]
      end

      let(:posts1) do
        double('PostsAssociation', count: 3)
      end

      let(:posts2) do
        double('PostsAssociation', count: 5)
      end

      let(:user1) do
        double('User', name: 'Alice', posts: posts1)
      end

      let(:user2) do
        double('User', name: 'Bob', posts: posts2)
      end

      before do
        allow(User).to receive(:find).with(101).and_return(user1)
        allow(User).to receive(:find).with(202).and_return(user2)
      end

      it 'queries each user and outputs the post counts' do
        expected_output = "Alice: 3 posts\nBob: 5 posts\n"
        expect do
          instance.generate_user_report(user_ids)
        end.to output(expected_output).to_stdout
        expect(User).to have_received(:find).with(101)
        expect(User).to have_received(:find).with(202)
      end
    end

    context 'with an empty user_ids array' do
      it 'does not query and outputs nothing' do
        expect(User).not_to receive(:find)
        expect do
          instance.generate_user_report([])
        end.to output('').to_stdout
      end
    end

    context 'when a user lookup fails' do
      let(:user_ids) do
        [1]
      end

      before do
        allow(User).to receive(:find).and_raise(StandardError, 'boom')
      end

      it 'propagates the error' do
        expect do
          instance.generate_user_report(user_ids)
        end.to raise_error(StandardError, 'boom')
      end
    end
  end

  describe '#build_csv' do
    context 'with multiple records' do
      let(:records) do
        [
          double('Record', id: 1, name: 'Alice'),
          double('Record', id: 2, name: 'Bob')
        ]
      end

      it 'returns a newline-separated CSV-like string' do
        expect(instance.build_csv(records)).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with an empty array' do
      it 'returns an empty string' do
        expect(instance.build_csv([])).to eq('')
      end
    end

    context 'when records is nil' do
      it 'raises an error' do
        expect do
          instance.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when a record is missing required attributes' do
      let(:records) do
        [double('Record', id: 1)]
      end

      it 'raises an error when trying to access name' do
        expect do
          instance.build_csv(records)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping elements' do
      it 'returns the common elements' do
        list_a = [1, 2, 3]
        list_b = [3, 4, 5]
        expect(instance.find_matches(list_a, list_b)).to eq([3])
      end
    end

    context 'with duplicates present' do
      it 'returns duplicates for each matching pair due to nested loops' do
        list_a = [1, 1]
        list_b = [1, 1]
        expect(instance.find_matches(list_a, list_b)).to eq([1, 1, 1, 1])
      end
    end

    context 'with no overlap' do
      it 'returns an empty array' do
        list_a = [1, 2]
        list_b = [3, 4]
        expect(instance.find_matches(list_a, list_b)).to eq([])
      end
    end

    context 'with empty lists' do
      it 'returns an empty array when list_a is empty' do
        expect(instance.find_matches([], [1, 2])).to eq([])
      end

      it 'returns an empty array when both lists are empty' do
        expect(instance.find_matches([], [])).to eq([])
      end
    end

    context 'when inputs are invalid' do
      it 'raises an error when list_b is nil' do
        expect do
          instance.find_matches([1, 2], nil)
        end.to raise_error(NoMethodError)
      end

      it 'raises an error when list_a is nil' do
        expect do
          instance.find_matches(nil, [1, 2])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    before do
      stub_const('User', Class.new)
    end

    context 'with multiple users' do
      let(:user1) do
        double('User1')
      end

      let(:user2) do
        double('User2')
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
        allow(instance).to receive(:send_email)
      end

      it 'loads all users and sends an email to each' do
        instance.process_all_users
        expect(instance).to have_received(:send_email).with(user1).once
        expect(instance).to have_received(:send_email).with(user2).once
      end
    end

    context 'with no users' do
      before do
        allow(User).to receive(:all).and_return([])
      end

      it 'does not call send_email' do
        expect(instance).not_to receive(:send_email)
        instance.process_all_users
      end
    end

    context 'when sending email fails' do
      let(:user1) do
        double('User1')
      end

      let(:user2) do
        double('User2')
      end

      before do
        allow(User).to receive(:all).and_return([user1, user2])
      end

      it 'propagates the error and stops processing' do
        allow(instance).to receive(:send_email).with(user1).and_raise(StandardError, 'smtp down')
        expect(instance).not_to receive(:send_email).with(user2)
        expect do
          instance.process_all_users
        end.to raise_error(StandardError, 'smtp down')
      end
    end
  end
end
