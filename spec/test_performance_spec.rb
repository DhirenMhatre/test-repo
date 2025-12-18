require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:generator) { described_class.new }

  describe '#generate_user_report' do
    let(:user1_posts) { double('Posts', count: 2) }
    let(:user2_posts) { double('Posts', count: 5) }
    let(:user1) { double('User', name: 'Alice', posts: user1_posts) }
    let(:user2) { double('User', name: 'Bob', posts: user2_posts) }

    before do
      stub_const('User', Class.new)
      allow(User).to receive(:find).with(1).and_return(user1)
      allow(User).to receive(:find).with(2).and_return(user2)
    end

    it 'prints a line for each user id with name and post count' do
      expect do
        generator.generate_user_report([1, 2])
      end.to output("Alice: 2 posts\nBob: 5 posts\n").to_stdout
    end

    context 'when user_ids is empty' do
      it 'prints nothing' do
        expect do
          generator.generate_user_report([])
        end.to output('').to_stdout
      end
    end

    context 'when a user lookup raises an error' do
      before do
        allow(User).to receive(:find).with(3).and_raise(StandardError, 'not found')
      end

      it 'propagates the error' do
        expect do
          generator.generate_user_report([3])
        end.to raise_error(StandardError, 'not found')
      end
    end

    context 'when user_ids is nil' do
      it 'raises an error' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    let(:record1) { double('Record', id: 1, name: 'Alpha') }
    let(:record2) { double('Record', id: 2, name: 'Beta') }

    it 'returns a CSV-like string with one row per record' do
      result = generator.build_csv([record1, record2])
      expect(result).to eq("1,Alpha\n2,Beta\n")
    end

    context 'when records is empty' do
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
      let(:bad_record) { double('Record', id: 3) }

      it 'raises an error' do
        expect do
          generator.build_csv([bad_record])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    it 'returns items that are equal between two lists, including duplicates' do
      matches = generator.find_matches([1, 1, 2], [1, 2, 2])
      expect(matches).to eq([1, 1, 2, 2])
    end

    context 'when there are no common items' do
      it 'returns an empty array' do
        expect(generator.find_matches([1, 3], [2, 4])).to eq([])
      end
    end

    context 'when one list is empty' do
      it 'returns an empty array for empty list_a' do
        expect(generator.find_matches([], [1, 2, 3])).to eq([])
      end

      it 'returns an empty array for empty list_b' do
        expect(generator.find_matches([1, 2, 3], [])).to eq([])
      end
    end

    context 'when inputs are nil' do
      it 'raises an error if list_a is nil' do
        expect do
          generator.find_matches(nil, [1, 2])
        end.to raise_error(NoMethodError)
      end

      it 'raises an error if list_b is nil' do
        expect do
          generator.find_matches([1, 2], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    let(:user_a) { double('User', id: 1) }
    let(:user_b) { double('User', id: 2) }

    before do
      stub_const('User', Class.new)
      allow(generator).to receive(:send_email)
    end

    context 'when there are users' do
      before do
        allow(User).to receive(:all).and_return([user_a, user_b])
      end

      it 'sends an email to each user' do
        generator.process_all_users
        expect(generator).to have_received(:send_email).with(user_a).once
        expect(generator).to have_received(:send_email).with(user_b).once
      end
    end

    context 'when there are no users' do
      before do
        allow(User).to receive(:all).and_return([])
      end

      it 'does not send any emails' do
        generator.process_all_users
        expect(generator).not_to have_received(:send_email)
      end
    end

    context 'when sending email raises an error' do
      before do
        allow(User).to receive(:all).and_return([user_a, user_b])
        allow(generator).to receive(:send_email).with(user_a).and_raise(RuntimeError, 'boom')
      end

      it 'propagates the error and stops processing' do
        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'boom')
        expect(generator).to have_received(:send_email).with(user_a).once
        expect(generator).not_to have_received(:send_email).with(user_b)
      end
    end
  end
end
