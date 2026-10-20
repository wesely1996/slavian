"""Walnut grain for the interface's wood (art id ui/wood): a seamless,
horizontally tiling texture of gently waving fibres, irregular growth
rings and pores, generated with numpy so it needs no image files."""
import sys

import numpy as np
from PIL import Image

def smooth1d(a, k):
    # circular box blur repeated (approx gaussian)
    for _ in range(3):
        a=(np.roll(a,1,-1)+a+np.roll(a,-1,-1))/3 if k==1 else sum(np.roll(a,i,-1) for i in range(-k,k+1))/(2*k+1)
    return a
def wood(W=512, H=256, seed=7):
    """The texture as a PIL image, W x H, tiling left to right."""
    rng=np.random.default_rng(seed)
    x=np.arange(W)[None,:]/W; y=np.arange(H)[:,None]/H
    # long gentle waves, periodic in x
    warp=np.zeros((H,W))
    for fx,amp in ((1,0.020),(2,0.012),(3,0.006)):
        ph=rng.uniform(0,2*np.pi); py=rng.uniform(0,2*np.pi)
        warp+=amp*np.sin(2*np.pi*fx*x+ph+np.sin(2*np.pi*y*1.5+py))
    yy=y+warp
    # growth rings: bands of varying width
    # irregular ring spacing: a smoothed random phase along y
    jit=rng.normal(0,1,(64,)); jit=np.convolve(np.concatenate([jit[-6:],jit,jit[:6]]),np.ones(7)/7,'same')[6:-6]
    jy=np.interp((yy%1.0)*64, np.arange(65), np.concatenate([jit,jit[:1]]))
    rings=np.sin(2*np.pi*(yy*11+0.9*jy))
    rings=np.sign(rings)*np.abs(rings)**2.2
    # fibres: random per-row value, smoothed across rows a little, stretched along x with slight variation
    rows=rng.normal(0,1,(H*4,))
    rows=np.convolve(np.concatenate([rows[-8:],rows,rows[:8]]),np.ones(5)/5,'same')[8:-8]
    idx=((yy*H*4).astype(int))%(H*4)
    fib=rows[idx]
    # pores: short dark dashes along x
    pores=rng.random((H,W))
    pores=smooth1d(pores,6)
    pores=(pores>0.62)*-0.15
    # streaks: per-row values that fade in and out along x
    rows2=rng.normal(0,1,(H*2,)); idx2=((yy*H*2).astype(int))%(H*2)
    streaks=rows2[idx2]*(0.5+0.5*np.sin(2*np.pi*(2*x+rows2[idx2]*0.2)))
    v=0.50+0.13*rings+0.10*fib+0.05*streaks+pores
    # broad light variation (periodic)
    v+=0.06*np.sin(2*np.pi*(x*1+0.3))*np.cos(2*np.pi*y)
    v=np.clip(v,0,1)
    dark=np.array([0x22,0x15,0x0d]); mid=np.array([0x47,0x2e,0x1d]); light=np.array([0x6d,0x48,0x2c])
    t=v[...,None]
    col=np.where(t<0.5, dark+(mid-dark)*(t/0.5), mid+(light-mid)*((t-0.5)/0.5))
    return Image.fromarray(col.astype(np.uint8),'RGB')
if __name__ == "__main__":
    wood().save(sys.argv[1])
