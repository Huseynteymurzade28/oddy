"""The colours of each world. Everything in tools/art draws from these, so a
world's mood is changed here and nowhere else."""


def hexc(s, a=255):
    s = s.lstrip('#')
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)


ZONES = {
    # A bright spring meadow: warm earth, fresh grass, a high blue sky.
    'mossy': dict(
        top=[hexc('#d6f77a'), hexc('#9be04a'), hexc('#5fb83a'), hexc('#3c8a35')],
        earth=[hexc('#e3a86a'), hexc('#c98952'), hexc('#a86a3d'), hexc('#7c4a2c'), hexc('#5a3322')],
        stone=[hexc('#f2d3a2'), hexc('#d9ae7c'), hexc('#9c7350')],
        outline=hexc('#3d2418'),
        flowers=[hexc('#ff7f9e'), hexc('#ffd84a'), hexc('#ffffff'), hexc('#b58cff'), hexc('#ff9d4a')],
        plank=[hexc('#f0c27a'), hexc('#d49a52'), hexc('#a8703a'), hexc('#6e4524')],
        rope=hexc('#e8d6a8'),
        liquid=[hexc('#e8fbff'), hexc('#8ee3f5'), hexc('#4cc1e6'), hexc('#2f93c9')],
        sky=[hexc('#4fb4ff'), hexc('#8fd3ff'), hexc('#d4f1ff'), hexc('#fff6d6')],
        clouds=[hexc('#ffffff'), hexc('#e2f2ff'), hexc('#bcdcf5')],
        far=[hexc('#9cc9f0'), hexc('#b8dcf7'), hexc('#ffffff')],
        mid=[hexc('#7fd06a'), hexc('#5cb456'), hexc('#3f9a4c')],
        near=[hexc('#4fa84a'), hexc('#37883f'), hexc('#2a6b36')],
        trunk=[hexc('#9a6a44'), hexc('#6e4a30')],
    ),
    # Sunlit ruins half under water: teal stone, sea moss, clear blue.
    'drowned': dict(
        style='bricks',
        top=[hexc('#c8ffd8'), hexc('#7fe0b0'), hexc('#43b88c'), hexc('#2e8a72')],
        earth=[hexc('#9ad0e6'), hexc('#6fb0d0'), hexc('#4f8fb6'), hexc('#3a6c94'), hexc('#284a6e')],
        stone=[hexc('#d6f2ff'), hexc('#a8d8f0'), hexc('#5e94bd')],
        outline=hexc('#1c2c4a'),
        flowers=[hexc('#ffe9a8'), hexc('#ff9fc0'), hexc('#ffffff'), hexc('#9ff5ff'), hexc('#ffc47a')],
        plank=[hexc('#d8e6ee'), hexc('#a9c3d3'), hexc('#7896ad'), hexc('#4b627d')],
        rope=hexc('#e6f0f5'),
        liquid=[hexc('#effcff'), hexc('#7fe6ff'), hexc('#3fb7e8'), hexc('#2a7fc4')],
        sky=[hexc('#2f8fd8'), hexc('#5ec2ec'), hexc('#a9e7f5'), hexc('#e9fff8')],
        clouds=[hexc('#f4fdff'), hexc('#d3f0fa'), hexc('#a8d6ea')],
        far=[hexc('#7fbfe0'), hexc('#a3d6ec'), hexc('#e6f8ff')],
        mid=[hexc('#5ca8c8'), hexc('#4691b4'), hexc('#367a9e')],
        near=[hexc('#3f8fa8'), hexc('#2f7492'), hexc('#235a78')],
        trunk=[hexc('#c9dde6'), hexc('#8eaabc')],
    ),
    # A warm volcanic dusk: dark rock with glowing seams, a peach sky.
    'ember': dict(
        style='basalt',
        top=[hexc('#ffe28a'), hexc('#ffb04a'), hexc('#e8742e'), hexc('#a8452a')],
        earth=[hexc('#8a5a6e'), hexc('#6e4258'), hexc('#553248'), hexc('#3e2438'), hexc('#2a1828')],
        stone=[hexc('#c9909e'), hexc('#a46a80'), hexc('#6e4258')],
        outline=hexc('#1a0e1a'),
        flowers=[hexc('#fff0a0'), hexc('#ff8a5a'), hexc('#ffd0e0'), hexc('#ffb84a'), hexc('#ff6a6a')],
        plank=[hexc('#b89aa6'), hexc('#8e7080'), hexc('#644a5a'), hexc('#3e2a38')],
        rope=hexc('#ffcf8a'),
        liquid=[hexc('#fff6b0'), hexc('#ffc84a'), hexc('#ff8a2e'), hexc('#d8482a')],
        sky=[hexc('#5a3a7a'), hexc('#c25a7c'), hexc('#ff9a6a'), hexc('#ffd88a')],
        clouds=[hexc('#ffd6c0'), hexc('#ffb0a0'), hexc('#d8808c')],
        far=[hexc('#9a5a7a'), hexc('#b8708a'), hexc('#ffb0a0')],
        mid=[hexc('#6e3a5e'), hexc('#5a2e50'), hexc('#4a2444')],
        near=[hexc('#4a2440'), hexc('#3a1a34'), hexc('#2a1228')],
        trunk=[hexc('#3a1a2a'), hexc('#2a1020')],
    ),
}
