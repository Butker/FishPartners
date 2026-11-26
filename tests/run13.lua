dofile(TESTS .. "/run9.lua")
local ns=FishPartners; local f=_G.FishPartnersHUD
ns.HUD:Show()
local cx, cy = 350, 314
GetCursorPosition=function() return cx, cy end
f.grip.scripts.OnMouseDown(f.grip, "LeftButton")
cx, cy = 350+250, 314   -- drag right by one window width -> ~2x
f.grip.scripts.OnUpdate(f.grip, 0.1)
f.grip.scripts.OnMouseUp(f.grip)
print("scale after drag:", f:GetScale(), "saved:", ns.S.hudScale, "anchor:", f.pt[1], f.pt[2], f.pt[3], f.pt[4])
cx = 50; f.grip.scripts.OnMouseDown(f.grip, "LeftButton"); cx = -400; f.grip.scripts.OnUpdate(f.grip, 0.1); f.grip.scripts.OnMouseUp(f.grip)
print("scale after shrinking hard (clamped):", f:GetScale())
f.grip.scripts.OnClick(f.grip, "RightButton"); print("after reset:", f:GetScale(), ns.S.hudScale)
ns.S.hudScale = 1.5; ns.HUD:ApplyScale(); print("settings stepper:", f:GetScale())
print("errors:", #ns.errors); print("OK13")
