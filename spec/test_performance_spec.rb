require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  subject(:generator) { described_class.new }

  describe '#generate_user_report' do
    let(:user_class) { class_double('User') }

    before do
      stub_const('User', user_class)
    end

    context 'with multiple user ids' do
      let(:posts1) { double('Posts1') }
      let(:posts2) { double('Posts2') }
      let(:user1) { instance_double('User', name: 'Alice', posts: posts1) }
      let(:user2) { instance_double('User', name: 'Bob', posts: posts2) }

      before do
        allow(posts1).to receive(:count).and_return(2)
        allow(posts2).to receive(:count).and_return(3)
        allow(user_class).to receive(:find).with(1).and_return(user1)
        allow(user_class).to receive(:find).with(2).and_return(user2)
      end

      it 'outputs the user names and post counts to stdout' do
        expect do
          generator.generate_user_report([1, 2])
        end.to output("Alice: 2 posts\nBob: 3 posts\n").to_stdout
      end

      it 'queries the database for each user id' do
        generator.generate_user_report([1, 2])
        expect(user_class).to have_received(:find).with(1).once
        expect(user_class).to have_received(:find).with(2).once
      end

      it 'calls count on posts for each user' do
        generator.generate_user_report([1, 2])
        expect(posts1).to have_received(:count).once
        expect(posts2).to have_received(:count).once
      end
    end

    context 'with empty user_ids' do
      it 'outputs nothing and returns nil' do
        result = nil
        expect do
          result = generator.generate_user_report([])
        end.to output('').to_stdout
        expect(result).to be_nil
      end
    end

    context 'when a lookup raises an error' do
      before do
        allow(user_class).to receive(:find).with(42).and_raise(StandardError, 'not found')
      end

      it 'propagates the error' do
        expect do
          generator.generate_user_report([42])
        end.to raise_error(StandardError, 'not found')
      end
    end

    context 'when posts association is missing' do
      let(:user) { instance_double('User', name: 'NoPosts') }

      before do
        allow(user_class).to receive(:find).with(7).and_return(user)
      end

      it 'raises an error' do
        expect do
          generator.generate_user_report([7])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    Record = Struct.new(:id, :name)

    let(:records) do
      [
        Record.new(1, 'Alice'),
        Record.new(2, 'Bob')
      ]
    end

    it 'builds a CSV string with id and name per line' do
      csv = generator.build_csv(records)
      expect(csv).to eq("1,Alice\n2,Bob\n")
    end

    context 'with empty records' do
      it 'returns an empty string' do
        expect(generator.build_csv([])).to eq('')
      end
    end

    context 'when records is nil' do
      it 'raises an error' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when a record is missing attributes' do
      let(:bad_record) { double('BadRecord', id: 1) }

      it 'raises an error' do
        expect do
          generator.build_csv([bad_record])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    it 'returns items present in both arrays' do
      result = generator.find_matches([1, 2, 3], [2, 3, 4])
      expect(result).to eq([2, 3])
    end

    it 'returns duplicates for multiple matches' do
      result = generator.find_matches([1, 2, 2], [2, 2])
      expect(result).to eq([2, 2, 2, 2])
    end

    it 'returns an empty array when there are no matches' do
      result = generator.find_matches([1, 5], [2, 3])
      expect(result).to eq([])
    end

    it 'returns an empty array when both lists are empty' do
      result = generator.find_matches([], [])
      expect(result).to eq([])
    end

    it 'raises an error when list_a is nil' do
      expect do
        generator.find_matches(nil, [1, 2])
      end.to raise_error(NoMethodError)
    end

    it 'raises an error when list_b is nil' do
      expect do
        generator.find_matches([1, 2], nil)
      end.to raise_error(NoMethodError)
    end
  end

  describe '#process_all_users' do
    let(:user_class) { class_double('User') }

    before do
      stub_const('User', user_class)
      allow(generator).to receive(:send_email)
    end

    context 'when there are users' do
      let(:user1) { instance_double('User', id: 1) }
      let(:user2) { instance_double('User', id: 2) }

      before do
        allow(user_class).to receive(:all).and_return([user1, user2])
      end

      it 'sends an email to each user' do
        generator.process_all_users
        expect(generator).to have_received(:send_email).with(user1).once
        expect(generator).to have_received(:send_email).with(user2).once
      end
    end

    context 'when there are no users' do
      before do
        allow(user_class).to receive(:all).and_return([])
      end

      it 'does not attempt to send any emails' do
        generator.process_all_users
        expect(generator).not_to have_received(:send_email)
      end
    end

    context 'when sending email raises an error' do
      let(:user1) { instance_double('User', id: 1) }
      let(:user2) { instance_double('User', id: 2) }

      before do
        allow(user_class).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email) do |user|
          raise 'boom' if user == user2
        end
      end

      it 'propagates the error after processing the first user' do
        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'boom')
        expect(generator).to have_received(:send_email).with(user1)
      end
    end

    context 'when fetching users raises an error' do
      before do
        allow(user_class).to receive(:all).and_raise(StandardError, 'db down')
      end

      it 'propagates the error' do
        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'db down')
      end
    end
  end
end
