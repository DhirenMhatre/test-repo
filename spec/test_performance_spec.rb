require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  let(:generator) { described_class.new }

  describe '#generate_user_report' do
    before do
      stub_const('User', Class.new)
    end

    context 'with valid user IDs' do
      let(:posts1) { double('Posts', count: 2) }
      let(:posts2) { double('Posts', count: 3) }
      let(:user1) { instance_double('UserInstance', name: 'Alice', posts: posts1) }
      let(:user2) { instance_double('UserInstance', name: 'Bob', posts: posts2) }

      before do
        allow(User).to receive(:find).with(1).and_return(user1)
        allow(User).to receive(:find).with(2).and_return(user2)
        allow(user1).to receive(:posts).and_return(posts1)
        allow(user2).to receive(:posts).and_return(posts2)
      end

      it 'prints a report line for each user' do
        expect do
          generator.generate_user_report([1, 2])
        end.to output("Alice: 2 posts\nBob: 3 posts\n").to_stdout
        expect(User).to have_received(:find).with(1)
        expect(User).to have_received(:find).with(2)
        expect(user1).to have_received(:posts).at_least(:once)
        expect(user2).to have_received(:posts).at_least(:once)
      end
    end

    context 'with an empty array' do
      it 'prints nothing' do
        expect do
          generator.generate_user_report([])
        end.to output('').to_stdout
      end
    end

    context 'when user_ids is nil' do
      it 'raises NoMethodError' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when a user lookup fails' do
      before do
        allow(User).to receive(:find).with(1).and_raise(StandardError, 'DB down')
      end

      it 'propagates the error' do
        expect do
          generator.generate_user_report([1])
        end.to raise_error(StandardError, 'DB down')
      end
    end
  end

  describe '#build_csv' do
    context 'with valid records' do
      let(:record1) { double('Record', id: 1, name: 'Alice') }
      let(:record2) { double('Record', id: 2, name: 'Bob') }

      it 'returns CSV lines for each record' do
        result = generator.build_csv([record1, record2])
        expect(result).to eq("1,Alice\n2,Bob\n")
      end
    end

    context 'with an empty array' do
      it 'returns an empty string' do
        result = generator.build_csv([])
        expect(result).to eq('')
      end
    end

    context 'when records is nil' do
      it 'raises NoMethodError' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'when a record has nil attributes' do
      let(:record) { double('Record', id: 1, name: nil) }

      it 'includes empty fields for nil values' do
        result = generator.build_csv([record])
        expect(result).to eq("1,\n")
      end
    end

    context 'when a record is missing required methods' do
      let(:bad_record) { double('Record') }

      it 'raises NoMethodError' do
        expect do
          generator.build_csv([bad_record])
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#find_matches' do
    context 'with overlapping elements' do
      it 'returns matches including duplicates as per nested loops' do
        list_a = [1, 2]
        list_b = [2, 2, 3]
        result = generator.find_matches(list_a, list_b)
        expect(result).to eq([2, 2])
      end
    end

    context 'with no overlaps' do
      it 'returns an empty array' do
        result = generator.find_matches([1, 4], [2, 3])
        expect(result).to eq([])
      end
    end

    context 'with empty lists' do
      it 'returns an empty array when list_a is empty' do
        result = generator.find_matches([], [1, 2, 3])
        expect(result).to eq([])
      end

      it 'returns an empty array when list_b is empty' do
        result = generator.find_matches([1, 2, 3], [])
        expect(result).to eq([])
      end
    end

    context 'with nil inputs' do
      it 'raises NoMethodError when list_a is nil' do
        expect do
          generator.find_matches(nil, [1, 2])
        end.to raise_error(NoMethodError)
      end

      it 'raises NoMethodError when list_b is nil' do
        expect do
          generator.find_matches([1, 2], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    before do
      stub_const('User', Class.new)
    end

    context 'with users present' do
      let(:user1) { double('User1') }
      let(:user2) { double('User2') }

      before do
        allow(User).to receive(:all).and_return([user1, user2])
        allow(generator).to receive(:send_email)
      end

      it 'sends an email to each user' do
        generator.process_all_users
        expect(generator).to have_received(:send_email).with(user1)
        expect(generator).to have_received(:send_email).with(user2)
      end
    end

    context 'with no users' do
      before do
        allow(User).to receive(:all).and_return([])
        allow(generator).to receive(:send_email)
      end

      it 'does not send any emails' do
        generator.process_all_users
        expect(generator).not_to have_received(:send_email)
      end
    end

    context 'when sending email fails' do
      let(:user1) { double('User1') }
      let(:user2) { double('User2') }

      before do
        allow(User).to receive(:all).and_return([user1, user2])
      end

      it 'propagates the error and stops processing' do
        expect(generator).to receive(:send_email).with(user1).and_raise('boom')
        expect do
          generator.process_all_users
        end.to raise_error(RuntimeError, 'boom')
      end
    end

    context 'when User.all returns nil' do
      before do
        allow(User).to receive(:all).and_return(nil)
      end

      it 'raises NoMethodError' do
        expect do
          generator.process_all_users
        end.to raise_error(NoMethodError)
      end
    end
  end
end
