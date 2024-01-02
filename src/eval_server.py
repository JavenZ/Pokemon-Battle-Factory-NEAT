import json
import os
import signal
import socket
import random
from collections.abc import MutableMapping
import PIL
import neat
import numpy as np
from scipy.signal import correlate
from skimage.measure import block_reduce
from neat.nn import FeedForwardNetwork
import subprocess
from PIL import Image
import io
import sys


class EvaluationServer:

    HOST = "127.0.0.1"  # Standard loopback interface address (localhost)
    PORT = 0  # Port to listen on (non-privileged ports are > 1023)
    EMU_PATH = '/home/javen/Desktop/PokeDS/BizHawk-2.9.1-linux-x64/EmuHawkMono.sh'
    KERNEL = np.array([[-1, -1, -1], [-1, 8, -1], [-1, -1, -1]])  # Edge Detection Kernel
    PNG_HEADER = b"\x89PNG"
    BF_STATE_HEADER = b"BF_STATE"
    READY_STATE = b"5 READY"
    FINISH_STATE = b"8 FINISHED"
    FITNESS_HEADER = b"FITNESS:"

    def __init__(self, game_mode: str):
        if game_mode == "open_world":
            self.EVAL_SCRIPT = "./src/eval_openworld.lua"
            self.ACTIONS = ['B', 'A', 'Y', 'X', 'Up', 'Down', 'Left', 'Right', 'Null']
        if game_mode == "battle_factory":
            self.EVAL_SCRIPT = "./src/eval_battlefactory.lua"
            # self.ACTIONS = ['B', 'A', 'Up', 'Down', 'Left', 'Right']
            self.ACTIONS = ['Move1', 'Move2', 'Move3', 'Move4', 'Poke1', 'Poke2', 'Poke3', 'Poke4', 'Poke5', 'Poke6']

    def eval_genomes(self, genomes, config) -> None:
        """
        Evaluates a population of genomes.
        """
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            print("Initializing socket server...")
            self.PORT = 0  # reset port
            # bind socket server
            s.bind((self.HOST, self.PORT))
            self.PORT = s.getsockname()[1]
            print(f'Socket server: listening on port {self.PORT }')
            s.listen()

            # spawn agent
            client_process = self.spawn_client()
            print("Spawned emulator client.")

            # wait for agent to connect to socket
            client, addr = s.accept()
            with client:
                print(f"Connected by {addr}.")
                try:
                    # evaluate each genome
                    for _id, genome in genomes:
                        # create NN from genome
                        nn = neat.nn.FeedForwardNetwork.create(genome, config)
                        print(f"\nGenome #: {_id}")

                        # wait for client to be ready
                        while True:
                            data = client.recv(1024)
                            if not data:
                                raise Exception("Connection closed before finishing evaluation.")
                            if data == self.READY_STATE:
                                print("Client is ready to evaluate next genome.")
                                client.sendall(self.READY_STATE)
                                break

                        # begin genome evaluation
                        fitness = self._eval(client, nn)
                        genome.fitness = fitness

                    # send finish state to client
                    data = client.recv(1024)
                    client.sendall(self.FINISH_STATE)
                    print("\nFinished evaluating genomes.")

                except Exception as e:
                    print(e)
                    os.killpg(os.getpgid(client_process.pid), signal.SIGTERM)

            # close server
            os.killpg(os.getpgid(client_process.pid), signal.SIGTERM)  # Send the signal to all the process groups
            s.shutdown(socket.SHUT_RDWR)
            s.close()

    def _eval(self, client, nn: FeedForwardNetwork) -> float:
        """
        Evaluates a single genome.
        """
        print("Evaluating genome...")
        # init fitness
        fitness = 0.0

        # repeat game loop
        while True:
            # receive client buffered message
            data = client.recv(30000)

            # client finished sending data
            if not data:
                raise Exception("Connection closed before finishing evaluation.")

            # calculate message data index
            m_index = self.calculate_mindex(data)

            # is msg a fitness score?
            if data[m_index:m_index + 8] == self.FITNESS_HEADER:
                print("Client is finished evaluating genome.")
                fitness = float(data[m_index + 8:])
                break

            # is msg a battle factory input state?
            if data[m_index:m_index + 8] == self.BF_STATE_HEADER:
                # print("Processing BF state...")
                # read and sort input state
                bf_state = json.loads(data[m_index + 8:])
                bf_state = self.sort_dict(bf_state)
                # print(json.dumps(bf_state, indent=4))

                # flatten input state
                bf_state = self.flatten_dict(bf_state)
                input_layer = np.array(list(bf_state.values()))

                # forward feed
                output_layer = nn.activate(input_layer)
                output_msg = "{ " + ", ".join([str(round(x, 10)) for x in output_layer]) + " }"
                # print(output_msg)

                # respond with output message
                client.sendall(b'' + bytes(f"{len(output_msg)} {output_msg}", 'utf-8'))

            # is msg a state screenshot?
            if data[m_index:m_index + 4] == self.PNG_HEADER:
                # print("Processing state screenshot...")
                outputs = self._ff_screenshot(data[m_index:], nn)
                decision = self.ACTIONS[outputs.index(max(outputs))]
                # decision = random.choice(self.DECISIONS)

                # respond to client with decision
                # print(f"Decision: {decision}")
                client.sendall(b'' + bytes(f"{len(decision)} {decision}", 'utf-8'))

        # return fitness score
        print(f"Genome fitness: {fitness}")
        return fitness

    def _ff_screenshot(self, png_data, nn):
        """
        Forward-feeds screenshot data through genome neural network.
        """
        # read image and convert to grayscale
        img = PIL.Image.open(io.BytesIO(png_data)).convert('L')
        # img.show()
        im = np.array(img)

        # convolve image
        im = correlate(im, self.KERNEL)
        # PIL.Image.fromarray(np.uint8(im * 255)).show()

        # reduce image dimensions
        im = block_reduce(im, block_size=(4, 4), func=np.average)
        # print(im.shape)
        # PIL.Image.fromarray(im).show()

        # forward feed
        im = im.reshape(-1)
        outputs = nn.activate(im)
        return outputs

    @classmethod
    def sort_dict(cls, item: dict):
        """
        Recursively sorts a nested dictionary.
        """
        for k, v in sorted(item.items()):
            item[k] = sorted(v) if isinstance(v, list) else v
        return {k: cls.sort_dict(v) if isinstance(v, dict) else v for k, v in sorted(item.items())}

    @classmethod
    def flatten_dict(cls, d: MutableMapping, parent_key: str = '', sep: str = '.') -> MutableMapping:
        items = []
        for k, v in d.items():
            new_key = parent_key + sep + k if parent_key else k
            if isinstance(v, MutableMapping):
                items.extend(cls.flatten_dict(v, new_key, sep=sep).items())
            else:
                items.append((new_key, v))
        return dict(items)

    @staticmethod
    def calculate_mindex(data):
        """
        Calculates the message index for the received data.
        """
        return data.find(b" ") + 1

    def spawn_client(self):
        """
        Spawns the emulator process and starts the eval_client.lua script.
        :return: None
        """
        return subprocess.Popen([
            self.EMU_PATH,
            f'--socket_port={self.PORT}',
            f'--socket_ip={self.HOST}',
            f'--lua={os.path.abspath(self.EVAL_SCRIPT)}'
        ], preexec_fn=os.setsid)
