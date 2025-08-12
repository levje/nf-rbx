# RecobundlesX Flow: streamline bundle extraction pipeline.

RecobundlesX is a popular streamline bundle extraction pipeline. This pipeline allows you to extract up to 24 bundles (when using the example atlas detailed below) from one or several whole brain tractograms for several subjects.

If you use this pipeline, please cite:
```
St-Onge, Etienne, Kurt G. Schilling, and Francois Rheault. "BundleSeg: A versatile, 
reliable and reproducible approach to white matter bundle segmentation." International 
Workshop on Computational Diffusion MRI. Cham: Springer Nature Switzerland, (2023)

Rheault, Francois. Analyse et reconstruction de faisceaux de la matière blanche.
page 137-170, (2020), https://savoirs.usherbrooke.ca/handle/11143/17255

Kurtzer GM, Sochat V, Bauer MW Singularity: Scientific containers for
mobility of compute. PLoS ONE 12(5): e0177459 (2017)
https://doi.org/10.1371/journal.pone.0177459

P. Di Tommaso, et al. Nextflow enables reproducible computational workflows.
Nature Biotechnology 35, 316–319 (2017) https://doi.org/10.1038/nbt.3820
```
## Requirements
- [Nextflow](https://www.nextflow.io/docs/latest/install.html)
- [Docker](https://www.docker.com/get-started/) or [Apptainer](https://apptainer.org/docs/admin/main/installation.html) depending on the runtime you choose.

## Getting started
### Understand the input
This nextflow pipeline has two mandatory arguments that the user has to provide in order to run the pipeline.
1. `--input`
2. `--atlas_directory`

Both of these arguments point to two different directories each having their own particular structure:
#### `--input`  
This argument points to the directory holding all the tractograms you wish to filter. Also, within this directory, each tractogram should be associated with an anatomical image (preferably the Fractional Anisotropy) in diffusion space. This image is used to compute the transformation from your diffusion space to the template space which is used to perform the bundle recognition task.

This said, the directory structure of your input should look like the following:
```bash
input_example
├── subject-01
│   ├── subject-01__fa.nii.gz
│   └── subject-01.trk
├── subject-02
│   ├── subject-02__fa.nii.gz
│   └── subject-02.tck
├── ...
└── subject-n
    ├── subject-n__fa.nii.gz
    └── subject-n.fib
```
The pipeline should support tractograms with one of the following extensions: `trk`,`tck`,`fib`,`vtk` or `dpy`.

#### `--atlas_directory`

In addition to your input, you also need to provide a path to the atlas that is used to perform the bundle extraction operation. RecobundlesX proposes an atlas that we recommend using for this pipeline, which requires to download and organize certain files (don't worry, it's very simple).

All you have to do is to paste the following commands into a terminal from a directory where you'd want the new `atlas_directory` to be stored.

```bash
wget https://zenodo.org/records/10103446/files/atlas.zip && wget https://zenodo.org/records/10103446/files/config.zip

mkdir -p atlas_directory

unzip atlas.zip -d atlas_directory
unzip config.zip -d atlas_directory
```

> If you don't have the `wget` and/or the `tar` commands and you don't want to (or can't) install them, you can always download the two archives manually from [here](https://zenodo.org/records/10103446/files/atlas.zip) and [here](https://zenodo.org/records/10103446/files/config.zip) and extract both archives into a common directory (which we call `atlas_directory` in our example). Just make sure that the directory structure looks like the following example.

From this point, the directory that you'll provide as a value to the `--atlas_directory` argument should have the following structure:
```
atlas_directory/
├── atlas
│   └── pop_average
│       └── ...
├── centroids
│   └── UF_R_centroid.trk
├── centroids_multi
│   └── ...
├── centroids_single
│   └── ...
├── config_fss_1.json
├── config_fss_2.json
└── mni_masked.nii.gz
```

Once those files are properly set up, all you have to do in the future is to point the `--atlas_directory` argument to this newly created directory.

### Usage
For the sake of simplicity, we list the following usage example which only contains the arguments you are most likely to use. To further customize your runtime experience, please refer to the [sections below](#complete-usage).
```bash
nextflow run levje/nf-rbx \
    --input <input_folder> \
    --atlas_directory </path/to/atlas_directory/> \
    -profile (docker | apptainer | ...) \
    [-resume]
```

**We recommend that most users specify either the `docker` or the `apptainer` profile** (but not both) depending on what is most accessible for you. This allows the tasks to run in prebuilt environments seemlessly which allows you to avoid installing and managing several dependencies (i.e. `scilpy` and `ants`).

#### About profiles  
We only listed the `docker` and `apptainer` profiles in the usage example above because they are 

#### Complete usage  
To get a complete list of the available arguments you can provide, you can always refer to the usage printed by the nextflow script as follows:
```bash
nextflow run levje/nf-rbx --help
```
