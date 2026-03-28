import json

base = 'C:/Users/yobk0/Documents/GitHub/LastEpochBuilding/src/TreeData/1_4/'

def fix_tree(filename, fixes_by_prefix):
    with open(base + filename, 'r', encoding='utf-8') as f:
        tree = json.load(f)
    nodes = tree['nodes']

    changes = []
    for key, node in nodes.items():
        prefix = None
        for p in fixes_by_prefix:
            if key.startswith(p + '-'):
                prefix = p
                break
        if prefix is None:
            continue

        fixes = fixes_by_prefix[prefix]
        name = node.get('name', '')

        if 'rename' in fixes and name in fixes['rename']:
            new_name = fixes['rename'][name]
            node['name'] = new_name
            changes.append(f'{key}: rename "{name}" -> "{new_name}"')
            name = new_name

        if 'maxpoints' in fixes and name in fixes['maxpoints']:
            old_val = node.get('maxPoints', 0)
            new_val = fixes['maxpoints'][name]
            node['maxPoints'] = new_val
            changes.append(f'{key}: {name} maxPoints {old_val} -> {new_val}')

        if 'disable' in fixes and name in fixes['disable']:
            old_val = node.get('maxPoints', 0)
            if old_val != 0:
                node['maxPoints'] = 0
                node['stats'] = []
                node['description'] = ''
                changes.append(f'{key}: DISABLE "{name}" (was maxPoints={old_val})')

    with open(base + filename, 'w', encoding='utf-8') as f:
        json.dump(tree, f, ensure_ascii=False, separators=(',', ':'))

    return changes

tree0_fixes = {
    'mas54': {
        'maxpoints': {'Turmoil': 4, 'Typhoon': 3}
    },
    'sbf4m': {
        'disable': ['Needle-Like Sting', 'Hornet Nest', "Grasshopper's Frenzy", "Viper's Call",
                    'Endless Pressure', 'Windfury Strikes', 'Army of the Tempest', 'Locust Master',
                    'Soaring Scourge', 'Carnage']
    },
    'sc36pi': {
        'disable': ['Cold-Blooded', 'Thunder Stinger', 'Reverberating Strike', 'Storm Conduit',
                    'Winternid Jaws', 'Rest for the WIcked']
    },
    'sp38': {
        'disable': ["Nature's Reach", 'Lasting Roots', 'Aura of Loyalty', 'Frostleaf',
                    'Aura of Evasion', 'Garden of Nourishment', 'Invading Underbrush',
                    'Thorny Stalks', 'Aura of Hordes', 'Aura of Voracity']
    },
    'to50': {
        'maxpoints': {'Voices of the Wind': 1, 'Shelter of the Storm': 4}
    },
    'uph41': {'maxpoints': {'Terrain Delving': 4}},
    'wo42': {'maxpoints': {'Lone Wolf': 1}},
}

tree1_fixes = {
    'bh2': {
        'maxpoints': {'Pocket Dimension': 1},
        'disable': ['Massive'],
    },
    'f1b4d': {
        'maxpoints': {'Flare': 4, 'Heat Wave': 3},
        'disable': ['Mana Shell'],
    },
    'fr11mv': {
        'maxpoints': {'Scorched Earth': 1},
        'disable': ['Volatile Strike', 'Firewalker'],
    },
    'frc87w': {
        'disable': ['Rending Cascade', 'Glamdring', 'Cold Star', 'Gift of Winter',
                    'Lava Talon', 'Spark Artillery', 'Fen of the Frozen', 'Brightfrost',
                    "Artor's Sceptre", 'Frost Beyond Time', 'Celestial Conflux',
                    'Cold and Calculating', 'Kolheim Ballista', 'Power Word: Hail',
                    'Shiver Shell', "Reowyn's Veil", 'Macuahuitl', 'Frozen Sleeper',
                    'Chaos Whirl', 'Age of Vengeance', 'On Through The Snow', 'Ever Onward',
                    'Frozen Malice', 'A Crack in the Ice', 'Hand of Morditas', 'Volley of Glass',
                    'Frozen Reign', 'Spark of Celerity'],
    },
    'me27': {
        'maxpoints': {
            'Infernal Descent': 4, 'Crushing Force': 4, 'Rapid Descent': 4,
            'Apocalyptic Impact': 4, 'Extinction': 3,
        }
    },
    'sb44eQ': {'maxpoints': {'Power Vent': 2}},
    'ss3tre': {
        'maxpoints': {
            'Icy Flow': 4, 'Razor Ice': 4, 'Iceblink': 4, 'Solidify': 4,
            'Unrelenting Winter': 4, 'Clash of Lightning': 1, 'Stormfused': 2,
        }
    },
    'st47ic': {'rename': {'Shock Armour': 'Shock Armor'}},
    'vo54': {
        'rename': {'Dense Orb': 'Volcanic Orb'},
        'maxpoints': {
            "Winter's Fury": 4, 'Ash Pelting': 4, 'Eruption': 5, 'Fiery Runes': 5,
        }
    },
}

tree2_fixes = {
    'ma6hdr': {
        'disable': ['Shield-Bearer', 'Lambent Metal', 'Thornmail', 'Blast Forge',
                    'Whirlwind', 'Dash Boots', 'Titan Sword'],
    },
}

tree3_fixes = {
    'bg36nl': {
        'maxpoints': {
            'Amalgam of Rogues': 4, 'Amalgam of Sentinels': 4,
            'Amalgam of Mages': 4, 'Marrow Eater': 2,
        }
    },
    'bp2nk': {
        'maxpoints': {
            'Ghost Splinters': 4, 'Ossumancy': 5, 'Shredding Bones': 4, 'Second Sight': 1,
        }
    },
    'ch4bo': {
        'rename': {
            'Sudden Putrescence ': 'Sudden Putrescence',
            'Seed of Chaos ': 'Seed of Chaos',
        }
    },
    'fl44': {'maxpoints': {'Spirit Stride': 3}},
    'sf31rc': {'maxpoints': {'Ivory Ballista': 2}},
    'sm4g': {
        'maxpoints': {
            'Gravetide': 4, 'Flaming Attacks': 4, 'Battle Hardened': 2, 'Forbidden Arcana': 4,
        }
    },
    'ss37kl': {
        'maxpoints': {'Unholy Rage': 4, 'Marrow Tap': 4, 'Ash and Frost': 1}
    },
    'svz81': {
        'maxpoints': {
            'Leap Attack': 3, 'Fervor': 4, 'Path of Destruction': 4, 'Forceful Commander': 4,
        },
        'rename': {'Ravenous ': 'Ravenous'},
        'disable': ['Daunting Blast'],
    },
    'ts50pl': {'maxpoints': {'Frozen Form': 1}},
}

tree4_fixes = {
    'dacn33': {'maxpoints': {'Underdog': 4, 'Rupture': 4}},
    'dagg3': {'rename': {'Excecution': 'Execution'}},
    'detar': {'rename': {'Deadly Ailments ': 'Deadly Ailments'}},
    'ex4tp': {'maxpoints': {'Lightning Bomb': 5}},
    'falc0': {'rename': {'Toxic Airdrop ': 'Toxic Airdrop'}},
    'ne01t': {
        'disable': ['Rending Wires', 'Advanced Engineering', 'Surprise Snare', 'Tanglewire',
                    'Tangled and Prone', 'Leading the Hunt', 'Quick Throws', 'Barbed Net',
                    'Voltaic Device', "Trapper's Crescendo", 'Curved Hooks', 'Acid Snare',
                    'Bold Throw', 'Net Trap', 'Spear Trap', 'Server of Tricks', 'Trickster Artist',
                    'Zone of Control', 'Silvered Spikes', "Tinkerer's Combo", 'Agile Hunter',
                    'Assault of the Huntress', 'Into the Shadows', 'Strongly Woven',
                    'Hunters of Heorot', 'Engineering Smarts', 'Acrobatic', 'Entangled Weapons',
                    'Exposed Bait', 'Weakening Threads'],
    },
    'ub5d9': {
        'maxpoints': {'Calling Card': 2},
        'disable': ['Cacophony of Steel', 'Steel Torrent', 'Loathing'],
    },
}

all_changes = []
for fname, fixes in [('tree_0.json', tree0_fixes), ('tree_1.json', tree1_fixes),
                      ('tree_2.json', tree2_fixes), ('tree_3.json', tree3_fixes),
                      ('tree_4.json', tree4_fixes)]:
    c = fix_tree(fname, fixes)
    all_changes += c
    print(f'{fname}: {len(c)} changes')

print(f'\nTotal: {len(all_changes)} changes')
for ch in all_changes:
    print(' ', ch)
