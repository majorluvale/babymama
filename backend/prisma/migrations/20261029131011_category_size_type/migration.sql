-- CreateEnum
CREATE TYPE "SizeType" AS ENUM ('CLOTHING', 'KIDS_AGE', 'SHOES', 'ONE_SIZE');

-- AlterTable
ALTER TABLE "Category" ADD COLUMN     "sizeType" "SizeType";
