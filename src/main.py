import os
import neat


class Trainer:
    def __init__(self, config_path: str):
        # Load configuration.
        self.config = neat.Config(
            neat.DefaultGenome, neat.DefaultReproduction,
            neat.DefaultSpeciesSet, neat.DefaultStagnation,
            config_path
        )

    def eval_genomes(self, genomes, config):
        for genome_id, genome in genomes:
            genome.fitness = 4.0
            net = neat.nn.FeedForwardNetwork.create(genome, config)
            # for xi, xo in zip(xor_inputs, xor_outputs):
            #     output = net.activate(xi)
            #     genome.fitness -= (output[0] - xo[0]) ** 2

    def run(self):
        # Create the population, which is the top-level object for a NEAT run.
        p = neat.Population(self.config)

        # Add a stdout reporter to show progress in the terminal.
        p.add_reporter(neat.StdOutReporter(True))
        stats = neat.StatisticsReporter()
        p.add_reporter(stats)
        p.add_reporter(neat.Checkpointer(5))

        # Run for up to 300 generations.
        winner = p.run(self.eval_genomes, 1)

        # Display the winning genome.
        print('\nBest genome:\n{!s}'.format(winner))

        # Show output of the most fit genome against training data.
        # print('\nOutput:')
        winner_net = neat.nn.FeedForwardNetwork.create(winner, self.config)
        # for xi, xo in zip(xor_inputs, xor_outputs):
        #     output = winner_net.activate(xi)
        #     print("input {!r}, expected output {!r}, got {!r}".format(xi, xo, output))
        #
        # node_names = {-1: 'A', -2: 'B', 0: 'A XOR B'}
        # visualize.draw_net(config, winner, True, node_names=node_names)
        # visualize.draw_net(config, winner, True, node_names=node_names, prune_unused=True)
        # visualize.plot_stats(stats, ylog=False, view=True)
        # visualize.plot_species(stats, view=True)

        # p = neat.Checkpointer.restore_checkpoint('neat-checkpoint-4')
        # p.run(self.eval_genomes, 10)


if __name__ == "__main__":
    pass
