require 'spec_helper'
require_relative '../test_performance'

RSpec.describe ReportGenerator do
  describe '#generate_user_report' do
    subject(:generator) do
      described_class.new
    end

    let(:user_class) do
      Class.new
    end

    before do
      stub_const('User', user_class)
    end

    context 'with multiple user ids' do
      let(:user1_posts) do
        double('Posts', count: 3)
      end

      let(:user2_posts) do
        double('Posts', count: 5)
      end

      let(:user1) do
        double('User', name: 'Alice')
      end

      let(:user2) do
        double('User', name: 'Bob')
      end

      it 'queries each user id, loads posts, and prints the report lines' do
        expect(user_class).to receive(:find).with(1).and_return(user1)
        expect(user_class).to receive(:find).with(2).and_return(user2)
        expect(user1).to receive(:posts).and_return(user1_posts)
        expect(user2).to receive(:posts).and_return(user2_posts)
        expect(user1_posts).to receive(:count).and_return(3)
        expect(user2_posts).to receive(:count).and_return(5)

        expect do
          generator.generate_user_report([1, 2])
        end.to output("Alice: 3 posts\nBob: 5 posts\n").to_stdout
      end
    end

    context 'with empty user_ids' do
      it 'prints nothing and returns nil' do
        expect do
          result = generator.generate_user_report([])
          expect(result).to be_nil
        end.to output('').to_stdout
      end
    end

    context 'when a lookup fails' do
      it 'propagates the error and stops processing further ids' do
        call_order = []
        allow(user_class).to receive(:find) do |id|
          call_order << id
          raise StandardError, 'not found' if id == 2

          double('User', name: 'First', posts: double('Posts', count: 1))
        end

        expect do
          generator.generate_user_report([1, 2, 3])
        end.to raise_error(StandardError, 'not found')

        expect(call_order).to eq([1, 2])
      end
    end

    context 'with nil input' do
      it 'raises an error' do
        expect do
          generator.generate_user_report(nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#build_csv' do
    subject(:generator) do
      described_class.new
    end

    let(:record1) do
      double('Record', id: 10, name: 'Alice')
    end

    let(:record2) do
      double('Record', id: 20, name: 'Bob')
    end

    context 'with records present' do
      it 'returns a CSV string with one row per record' do
        result = generator.build_csv([record1, record2])
        expect(result).to eq("10,Alice\n20,Bob\n")
      end
    end

    context 'with an empty array' do
      it 'returns an empty string' do
        result = generator.build_csv([])
        expect(result).to eq('')
      end
    end

    context 'with nil input' do
      it 'raises an error' do
        expect do
          generator.build_csv(nil)
        end.to raise_error(NoMethodError)
      end
    end

    context 'with records having numeric and special-character names' do
      let(:record3) do
        double('Record', id: 3, name: 'Ann, "The Great"')
      end

      it 'embeds values directly without escaping (as implemented)' do
        result = generator.build_csv([record3])
        expect(result).to eq("3,Ann, \"The Great\"\n")
      end
    end
  end

  describe '#find_matches' do
    subject(:generator) do
      described_class.new
    end

    context 'with overlapping elements' do
      it 'returns each matching element for each occurrence in list_b' do
        list_a = [1, 2, 2, 3]
        list_b = [2, 2, 4]
        result = generator.find_matches(list_a, list_b)
        expect(result).to eq([2, 2, 2, 2])
      end
    end

    context 'with no overlap' do
      it 'returns an empty array' do
        result = generator.find_matches([1, 3], [2, 4])
        expect(result).to eq([])
      end
    end

    context 'with empty arrays' do
      it 'returns an empty array' do
        result = generator.find_matches([], [])
        expect(result).to eq([])
      end
    end

    context 'with nil input' do
      it 'raises an error' do
        expect do
          generator.find_matches(nil, [1, 2])
        end.to raise_error(NoMethodError)

        expect do
          generator.find_matches([1, 2], nil)
        end.to raise_error(NoMethodError)
      end
    end
  end

  describe '#process_all_users' do
    subject(:generator) do
      described_class.new
    end

    let(:user_class) do
      Class.new
    end

    before do
      stub_const('User', user_class)
    end

    context 'when there are users' do
      let(:u1) do
        double('User', id: 1)
      end

      let(:u2) do
        double('User', id: 2)
      end

      it 'calls User.all and sends an email to each user' do
        users = [u1, u2]
        expect(users).to receive(:each).and_call_original
        allow(user_class).to receive(:all).and_return(users)
        expect(generator).to receive(:send_email).with(u1).ordered
        expect(generator).to receive(:send_email).with(u2).ordered

        result = generator.process_all_users
        expect(result).to be_nil
      end
    end

    context 'when there are no users' do
      it 'does not send any emails' do
        empty = []
        expect(empty).to receive(:each).and_call_original
        allow(user_class).to receive(:all).and_return(empty)
        expect(generator).not_to receive(:send_email)
        generator.process_all_users
      end
    end

    context 'when sending email fails for a user' do
      it 'propagates the error after attempting the failing user' do
        u1 = double('User', id: 1)
        u2 = double('User', id: 2)
        allow(user_class).to receive(:all).and_return([u1, u2])
        expect(generator).to receive(:send_email).with(u1).ordered
        expect(generator).to receive(:send_email).with(u2).and_raise(StandardError, 'smtp fail')

        expect do
          generator.process_all_users
        end.to raise_error(StandardError, 'smtp fail')
      end
    end
  end
end
