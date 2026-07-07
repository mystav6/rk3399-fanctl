########################################
# FAN CONTROL ENDPOINTY
# Přidat do api.py za T4-1 ENDPOINTY
########################################

@app.route("/api/fan/status/<device>", methods=["GET"])
def fan_status(device):
    """
    Reads live fan status directly from the device via SSH.
    Returns rk3399-fanctl --export-json output as JSON.

    GET /api/fan/status/t41  → fan data from T4-1
    GET /api/fan/status/t42  → fan data from T4-2
    """
    cmd = "sudo rk3399-fanctl --export-json 2>/dev/null"

    if device == "t41":
        result = ssh_t41(cmd)
    elif device == "t42":
        result = ssh_t42(cmd)
    else:
        return jsonify({"ok": False, "error": f"Unknown device: {device}"}), 400

    if not result["ok"] or not result["output"].strip():
        return jsonify({
            "ok": False,
            "error": f"Cannot reach {device} or rk3399-fanctl not installed",
            "device": device
        }), 503

    try:
        fan_data = json.loads(result["output"].strip())
        return jsonify({
            "ok": True,
            "device": device,
            "fan": fan_data,
            "timestamp": int(time.time())
        })
    except json.JSONDecodeError:
        return jsonify({
            "ok": False,
            "error": "Invalid JSON from rk3399-fanctl",
            "raw": result["output"][:200]
        }), 500


@app.route("/api/fan/set/<device>", methods=["POST"])
def fan_set(device):
    """
    Sets cooling-levels on the device via SSH.
    Requires JSON body: {"levels": "0,32,96,255"} or {"min_pwm": 30}

    POST /api/fan/set/t41  {"levels": "0,32,96,255"}
    POST /api/fan/set/t41  {"min_pwm": 30}

    NOTE: Restricted to LAN/VPN only via nginx (same as /api/ endpoints).
    """
    data = request.get_json(silent=True) or {}

    levels  = data.get("levels")
    min_pwm = data.get("min_pwm")

    if levels:
        cmd = f"sudo rk3399-fanctl --levels {levels} 2>&1"
    elif min_pwm is not None:
        cmd = f"sudo rk3399-fanctl --min-pwm {min_pwm} 2>&1"
    else:
        return jsonify({"ok": False, "error": "Provide 'levels' or 'min_pwm'"}), 400

    if device == "t41":
        result = ssh_t41(cmd)
    elif device == "t42":
        result = ssh_t42(cmd)
    else:
        return jsonify({"ok": False, "error": f"Unknown device: {device}"}), 400

    return jsonify({
        "ok": result["ok"],
        "device": device,
        "output": result["output"].strip()
    })
