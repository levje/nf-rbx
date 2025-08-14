import argparse
import json


def parse_args():
    parser = argparse.ArgumentParser(
        description="Compile reports from Nextflow outputs"
    )
    parser.add_argument(
        "--results",
        help="results.json file from the RECOGNIZE_BUNDLES process.",
        required=True,
    )
    parser.add_argument(
        "--cleaning_reports",
        nargs="+",
        help="cleaning reports from the CLEAN_BUNDLES process.",
        required=True,
    )
    parser.add_argument("--out_report", help="Output report file.", required=True)
    return parser.parse_args()


def main(args):
    results = json.load(open(args.results, "r"))

    bundles_indices = {}
    for bundle in results.keys():
        bundles_indices[bundle] = results[bundle]["indices"]

    for cleaning_report_file in args.cleaning_reports:
        # The cleaning report file name is structured like the following:
        # ${meta.id}__{bname}_report.json
        bname = cleaning_report_file.split("__")[-1].split("_report.json")[0]

        with open(cleaning_report_file, "r") as f:
            cleaning_report = json.load(f)
            inliers = cleaning_report["inliers"]

            # Keep only the indices which are at the location pointed by the inliers
            recognized_indices = bundles_indices[bname]

            new_indices = []
            for inlier in inliers:
                new_indices.append(recognized_indices[inlier])

            bundles_indices[bname] = new_indices

    # Write which indices belong to which bundle
    with open(args.out_report, "w") as f:
        json.dump(bundles_indices, f, indent=4)


if "__main__" == __name__:
    main(parse_args())
