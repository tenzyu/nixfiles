import json, pathlib, copy
p=pathlib.Path("evidence")
data=json.loads((p/"snapshots.json").read_text())
for k in ("baseline","candidate","control","gameDrvs"):
    (p/(k+".json")).write_text(json.dumps(data[k],sort_keys=True,indent=2)+"\n")
assert data["baseline"] == data["control"], "Counterfactual system identity differs"
a,b=data["baseline"],copy.deepcopy(data["candidate"])
pairs=[(a["nixos"]["neko7"],b["nixos"]["neko7"],"baseline","candidate"),(a["allGames"],b["allGames"],"baselineAll","candidateAll")]
for old,new,oldkey,newkey in pairs:
    olddrv,newdrv=data["gameDrvs"][oldkey],data["gameDrvs"][newkey]
    assert olddrv!=newdrv and new["packages"].count(newdrv)==1 and old["packages"].count(olddrv)==1
    new["packages"]=[olddrv if v==newdrv else v for v in new["packages"]]
    new["systemDrv"]=old["systemDrv"]
    new["systemUnits"]=old["systemUnits"]
assert a==b, "Unexplained difference outside the game package and its system derivation/unit references"
print("Counterfactual exact equality; raw change limited to game package and dependent host system outputs")
