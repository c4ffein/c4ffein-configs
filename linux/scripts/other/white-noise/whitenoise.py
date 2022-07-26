#!/usr/bin/env python

# Partly from
# https://stackoverflow.com/questions/66132799/generating-audio-noise
# https://stackoverflow.com/a/66136106/10161950

# With scipy, you can save numpy array as a .wav file.
# You just need to generate a sequence of random samples from normal distribution with zero mean.
# truncnorm is truncated normal distribution, which makes sure the sample values are not too big or too small
# (+- 2^16 in case of 16 bit .wav files)

from scipy.io import wavfile
from scipy import stats
import numpy as np
import io
import asyncio


async def get_sound():
    sample_rate = 44100
    length_in_seconds = 1
    amplitude = 11
    noise = stats.truncnorm(-1, 1, scale=min(2 ** 16, 2 ** amplitude)).rvs(sample_rate * length_in_seconds)
    f = io.BytesIO()
    wavfile.write(f, sample_rate, noise.astype(np.int16))
    return f.read()


async def play_sound(wav):
    p = await asyncio.create_subprocess_shell("aplay -q", stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE)
    # We could try looping `p.stdin.write`, except aplay seems to quit after the declared lenght of the .wav
    # See await p.communicate(wav + wav + wav) : just overlapping pla_sound then...
    stdout, stderr = await p.communicate(wav)


async def main():
    rps = 4
    sp = [[asyncio.create_task(get_sound()), None, None] for _ in range(rps)]  # current_wav, next_wav, playing
    while True:
        for i in range(rps):
            sp[i][1] = asyncio.create_task(get_sound())
            sp[i][2] = asyncio.create_task(play_sound(await sp[i][0]))
            await asyncio.sleep(1 / rps)
            sp[i][0] = sp[i][1]


if __name__ == "__main__":
    asyncio.run(main())
