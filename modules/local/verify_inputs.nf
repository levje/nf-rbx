def check_required_params(param_names) {
    // Loop through each parameter name and check if it exists in params
    // We need to accumulate errors to report them all at once
    def missing_params = []
    param_names.each { param ->
        if (!params.containsKey(param) || params[param] == false || params[param] == '' || params[param] == null) {
            missing_params << param
        }
    }

    if (missing_params) {
        throw new Exception("Missing required parameters: ${missing_params.join(', ')}")
    }
}

def check_nb_cpus() {
    if(params.processes) {
        if(params.processes > Runtime.runtime.availableProcessors()) {
            throw new RuntimeException("Number of processes higher than available CPUs.")
        }
        else if(params.processes < 1) {
            throw new RuntimeException("When set, number of processes must be >= 1 " +
                                    "and smaller or equal to the number of CPUs.")
        }
    }
}